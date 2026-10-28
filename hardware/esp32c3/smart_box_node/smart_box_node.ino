/*
 * 慧药管家 ESP32-C3 联网节点
 *
 * LD2410C -> GPIO20/21, SYN6288 RXD -> GPIO7
 * 功能:
 *   1. 雷达有人/无人上报后端
 *   2. 从后端领取播报文本（后端同时返回 GB2312 Base64）
 *   3. 小智进入 listening/speaking 时停止 SYN6288
 *   4. 上报 SYN6288 speaking/idle 状态
 *
 * 使用前把 secrets.h.example 复制为 secrets.h 并填写 WiFi、服务器和设备令牌。
 */
#include <Arduino.h>
#include <WiFiClientSecure.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <mbedtls/base64.h>

#include "secrets.h"

static const int RADAR_RX_PIN = 20;
static const int RADAR_TX_PIN = 21;
static const int TTS_TX_PIN = 7;
static const int TTS_RX_PIN = 6;

static const uint16_t TRIGGER_CM = 150;
static const uint32_t PRESENCE_MS = 3000;
static const uint32_t RADAR_POST_INTERVAL_MS = 3000;
static const uint32_t ANNOUNCEMENT_POLL_MS = 1500;
static const uint32_t RUNTIME_POLL_MS = 1000;

HardwareSerial Radar(0);
HardwareSerial Tts(1);

WiFiClientSecure secureClient;

uint8_t p_state = 0;
uint16_t p_len = 0;
uint16_t p_pos = 0;
uint8_t payload[32];

bool present = false;
uint32_t last_seen = 0;
uint16_t last_distance = 0;
uint32_t last_radar_post = 0;
uint32_t last_announcement_poll = 0;
uint32_t last_runtime_poll = 0;
uint32_t speaking_until = 0;
bool syn_speaking = false;
int active_announcement_id = 0;
String last_stop_timestamp = "";
unsigned long last_wifi_attempt = 0;
bool wifi_reported = false;

static const uint8_t LOCAL_FALLBACK_PHRASE[] = {
  0xBC,0xEC,0xB2,0xE2,0xB5,0xBD,0xD3,0xD0,0xC8,0xCB,0xA3,0xAC,
  0xC7,0xEB,0xB0,0xB4,0xCA,0xB1,0xB7,0xFE,0xD2,0xA9,0xA1,0xA3
};

String apiUrl(const String& path) {
  return String(SMB_BASE_URL) + path;
}

bool httpJson(const String& method, const String& path, const String& body, JsonDocument& doc, int* statusCode = nullptr) {
  if (WiFi.status() != WL_CONNECTED) return false;
  HTTPClient http;
  http.setTimeout(5000);
  if (!http.begin(secureClient, apiUrl(path))) return false;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Agent-Token", SMB_AGENT_TOKEN);
  int code = method == "POST" ? http.POST(body) : http.GET();
  if (statusCode) *statusCode = code;
  bool ok = code >= 200 && code < 300;
  if (ok) {
    DeserializationError error = deserializeJson(doc, http.getString());
    ok = !error;
  }
  http.end();
  return ok;
}

void postSynState(const char* state) {
  JsonDocument payloadDoc;
  payloadDoc["device_uid"] = SMB_DEVICE_UID;
  payloadDoc["state"] = state;
  if (active_announcement_id > 0) payloadDoc["announcement_id"] = active_announcement_id;
  String body;
  serializeJson(payloadDoc, body);
  JsonDocument response;
  httpJson("POST", "/api/v1/device-agent/syn6288/state", body, response);
}

void postRadar(bool isPresent) {
  JsonDocument doc;
  doc["device_uid"] = SMB_DEVICE_UID;
  doc["present"] = isPresent;
  doc["distance_cm"] = last_distance;
  String body;
  serializeJson(doc, body);
  JsonDocument response;
  httpJson("POST", "/api/v1/device-agent/radar/events", body, response);
  last_radar_post = millis();
}

void speakGb2312(const uint8_t* data, size_t len) {
  if (len == 0 || len > 200) return;
  uint8_t frame[210];
  frame[0] = 0xFD;
  frame[1] = 0x00;
  frame[2] = (uint8_t)(len + 3);
  frame[3] = 0x01;
  frame[4] = 0x00;
  memcpy(frame + 5, data, len);
  uint8_t checksum = 0;
  for (size_t i = 0; i < 5 + len; i++) checksum ^= frame[i];
  frame[5 + len] = checksum;
  Tts.write(frame, 6 + len);
  Tts.flush();
  Serial.printf("[TTS] speaking %u bytes\n", (unsigned)len);
}

void stopSyn() {
  static const uint8_t STOP_FRAME[] = {0xFD, 0x00, 0x02, 0x02, 0xFD};
  Tts.write(STOP_FRAME, sizeof(STOP_FRAME));
  Tts.flush();
  Serial.println("[TTS] stop");
  if (syn_speaking) {
    syn_speaking = false;
    speaking_until = 0;
    active_announcement_id = 0;
  }
}

int decodeBase64(const String& encoded, uint8_t* output, size_t outputSize) {
  size_t decodedLength = 0;
  int result = mbedtls_base64_decode(
      output,
      outputSize,
      &decodedLength,
      reinterpret_cast<const unsigned char*>(encoded.c_str()),
      encoded.length());
  return result == 0 ? (int)decodedLength : -1;
}

void pollRuntime() {
  JsonDocument doc;
  if (!httpJson("GET", String("/api/v1/device-agent/runtime?device_uid=") + SMB_DEVICE_UID, "", doc)) return;
  String stopAt = doc["stop_tts_requested_at"] | "";
  if (stopAt.length() > 0 && stopAt != last_stop_timestamp) {
    last_stop_timestamp = stopAt;
    stopSyn();
  }
}

void pollAnnouncement() {
  if (syn_speaking) return;
  JsonDocument doc;
  String path = String("/api/v1/device-agent/announcements/next?device_uid=") + SMB_DEVICE_UID;
  if (!httpJson("GET", path, "", doc)) return;
  JsonObject announcement = doc["announcement"].as<JsonObject>();
  if (announcement.isNull()) return;
  String encoded = announcement["text_gb2312_base64"] | "";
  if (encoded.length() == 0) return;
  uint8_t text[210];
  int decoded = decodeBase64(encoded, text, sizeof(text));
  if (decoded <= 0) {
    Serial.println("[TTS] base64 decode failed");
    return;
  }
  active_announcement_id = announcement["id"] | 0;
  syn_speaking = true;
  uint32_t estimatedMs = (uint32_t)decoded * 230UL;
  if (estimatedMs < 3000) estimatedMs = 3000;
  speaking_until = millis() + estimatedMs;
  speakGb2312(text, (size_t)decoded);
  postSynState("speaking");
}

void parseFrame() {
  if (p_len < 13) return;
  if (payload[0] != 0x02 || payload[1] != 0xAA) return;
  uint8_t target = payload[2];
  uint16_t moving = (uint16_t)payload[3] | ((uint16_t)payload[4] << 8);
  uint16_t still = (uint16_t)payload[6] | ((uint16_t)payload[7] << 8);
  uint16_t detect = (uint16_t)payload[9] | ((uint16_t)payload[10] << 8);
  uint32_t now = millis();
  if (target != 0) {
    bool was_present = present;
    present = true;
    last_seen = now;
    last_distance = detect ? detect : (moving ? moving : still);
    Serial.printf("[RADAR] present detect=%ucm moving=%ucm static=%ucm\n", detect, moving, still);
    if (!was_present && last_distance > 0 && last_distance <= TRIGGER_CM) {
      postRadar(true);
    }
  } else if (present) {
    present = false;
    Serial.println("[RADAR] none");
    postRadar(false);
  }
}

void feed(uint8_t b) {
  switch (p_state) {
    case 0: if (b == 0xF4) p_state = 1; break;
    case 1: p_state = (b == 0xF3) ? 2 : (b == 0xF4 ? 1 : 0); break;
    case 2: p_state = (b == 0xF2) ? 3 : (b == 0xF4 ? 1 : 0); break;
    case 3: p_state = (b == 0xF1) ? 4 : (b == 0xF4 ? 1 : 0); break;
    case 4: p_len = b; p_state = 5; break;
    case 5:
      p_len |= (uint16_t)b << 8;
      p_pos = 0;
      p_state = (p_len > 0 && p_len <= sizeof(payload)) ? 6 : 0;
      break;
    case 6:
      payload[p_pos++] = b;
      if (p_pos >= p_len) {
        parseFrame();
        p_state = 0;
      }
      break;
    default: p_state = 0; break;
  }
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  unsigned long now = millis();
  if (last_wifi_attempt != 0 && now - last_wifi_attempt < 10000) return;
  last_wifi_attempt = now;
  Serial.printf("[WiFi] connecting to %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Radar.begin(256000, SERIAL_8N1, RADAR_RX_PIN, RADAR_TX_PIN);
  Tts.begin(9600, SERIAL_8N1, TTS_RX_PIN, TTS_TX_PIN);
  secureClient.setInsecure();
  connectWifi();
  Serial.println();
  Serial.println("慧药管家 ESP32-C3 node ready");
}

void loop() {
  while (Radar.available()) feed(Radar.read());

  if (present && millis() - last_seen > PRESENCE_MS) {
    present = false;
    Serial.println("[RADAR] timeout -> none");
    postRadar(false);
  }

  if (present && millis() - last_radar_post > RADAR_POST_INTERVAL_MS) {
    postRadar(true);
  }

  if (WiFi.status() != WL_CONNECTED) {
    wifi_reported = false;
    connectWifi();
  } else {
    if (!wifi_reported) {
      wifi_reported = true;
      Serial.printf("[WiFi] connected ip=%s\n", WiFi.localIP().toString().c_str());
      postSynState("idle");
    }
    if (millis() - last_runtime_poll >= RUNTIME_POLL_MS) {
      last_runtime_poll = millis();
      pollRuntime();
    }
    if (millis() - last_announcement_poll >= ANNOUNCEMENT_POLL_MS) {
      last_announcement_poll = millis();
      pollAnnouncement();
    }
  }

  if (syn_speaking && millis() >= speaking_until) {
    syn_speaking = false;
    speaking_until = 0;
    postSynState("idle");
    active_announcement_id = 0;
    Serial.println("[TTS] estimated playback finished");
  }

  if (Serial.available()) {
    char c = (char)Serial.read();
    if (c == 't' || c == 'T') {
      Serial.println("[TEST] local fallback phrase");
      speakGb2312(LOCAL_FALLBACK_PHRASE, sizeof(LOCAL_FALLBACK_PHRASE));
    } else if (c == 's' || c == 'S') {
      stopSyn();
    }
  }
  delay(5);
}
