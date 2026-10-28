/*
 * 慧药管家 - 阶段 1 自检固件
 * 雷达 LD2410C -> ESP32-C3 -> SYN6288 播报
 *
 * 目的：不联网、不接服务器，只验证三件事
 *   1. 雷达能读到有人/无人和距离
 *   2. 播报模块能念出中文
 *   3. 两者串起来：人走近就播报
 *
 * 接线（ESP32-C3 SuperMini）：
 *   LD2410C  VCC -> 5V        GND -> GND
 *            TX  -> GPIO20     RX  -> GPIO21
 *   SYN6288  VCC -> 5V        GND -> GND
 *            RXD -> GPIO7
 *   小喇叭    接 SYN6288 的 SPK+ / SPK-
 *
 * 注意：两个模块都用 5V 供电，串口电平 3.3V，可直连。
 */

#include <Arduino.h>

static const int RADAR_RX_PIN = 20;
static const int RADAR_TX_PIN = 21;
static const int TTS_TX_PIN   = 7;
static const int TTS_RX_PIN   = 6;

HardwareSerial Radar(0);
HardwareSerial Tts(1);

// "检测到有人，请按时服药。" 的 GB2312 编码
static const uint8_t PHRASE[] = {
  0xBC,0xEC,0xB2,0xE2,0xB5,0xBD,0xD3,0xD0,0xC8,0xCB,0xA3,0xAC,
  0xC7,0xEB,0xB0,0xB4,0xCA,0xB1,0xB7,0xFE,0xD2,0xA9,0xA1,0xA3
};

static const uint16_t TRIGGER_CM    = 150;   // 1.5 米内触发
static const uint32_t COOLDOWN_MS   = 30000; // 两次播报至少间隔 30 秒
static const uint32_t PRESENCE_MS   = 3000;  // 3 秒无数据视为离开

// ---- 雷达帧解析状态机 ----
uint8_t  p_state = 0;
uint16_t p_len = 0;
uint16_t p_pos = 0;
uint8_t  payload[32];

bool     present = false;
uint32_t last_seen = 0;
uint32_t last_speak = 0;
uint16_t last_distance = 0;
uint32_t radar_bytes = 0;
uint32_t radar_frames = 0;
uint32_t last_radar_report = 0;

void speakGb2312(const uint8_t* data, size_t len) {
  if (len == 0 || len > 200) return;

  // SYN6288 frame: FD | data length (2 bytes) | command |
  // command parameter | GB2312 text | XOR checksum.
  uint8_t frame[210];
  frame[0] = 0xFD;
  frame[1] = 0x00;                  // Length high byte
  frame[2] = (uint8_t)(len + 3);    // Command + parameter + checksum
  frame[3] = 0x01;                  // Synthesize and play
  frame[4] = 0x00;                  // GB2312 encoding
  memcpy(frame + 5, data, len);

  uint8_t x = 0;
  for (size_t i = 0; i < 5 + len; i++) x ^= frame[i];
  frame[5 + len] = x;

  Tts.write(frame, 6 + len);
  Tts.flush();
  Serial.println("[TTS] sent");
}

void parseFrame() {
  // Basic target frame: 02 AA | state | moving distance | ...
  if (p_len < 13) return;
  if (payload[0] != 0x02 || payload[1] != 0xAA) return;
  radar_frames++;

  uint8_t  target  = payload[2];
  uint16_t moving  = (uint16_t)payload[3] | ((uint16_t)payload[4] << 8);
  uint16_t still   = (uint16_t)payload[6] | ((uint16_t)payload[7] << 8);
  uint16_t detect  = (uint16_t)payload[9] | ((uint16_t)payload[10] << 8);

  uint32_t now = millis();
  if (target != 0) {
    present = true;
    last_seen = now;
    last_distance = detect ? detect : (moving ? moving : still);
    Serial.printf("[RADAR] target=%u detect=%ucm moving=%ucm static=%ucm\n",
                  target, detect, moving, still);

    if (last_distance > 0 && last_distance <= TRIGGER_CM &&
        (last_speak == 0 || now - last_speak >= COOLDOWN_MS)) {
      last_speak = now;
      Serial.println("[TRIGGER] speak");
      speakGb2312(PHRASE, sizeof(PHRASE));
    }
  } else {
    present = false;
    Serial.println("[RADAR] none");
  }
}

void feed(uint8_t b) {
  switch (p_state) {
    // LD2410C target-report frames start with F4 F3 F2 F1.
    case 0: if (b == 0xF4) p_state = 1; break;
    case 1: p_state = (b == 0xF3) ? 2 : (b == 0xF4 ? 1 : 0); break;
    case 2: p_state = (b == 0xF2) ? 3 : (b == 0xF4 ? 1 : 0); break;
    case 3:
      if (b == 0xF1) { p_state = 4; }
      else p_state = (b == 0xF4 ? 1 : 0);
      break;
    case 4: p_len = b; p_state = 5; break;
    case 5:
      p_len |= (uint16_t)b << 8;
      p_pos = 0;
      p_state = (p_len > 0 && p_len <= sizeof(payload)) ? 6 : 0;
      break;
    case 6:
      payload[p_pos++] = b;
      if (p_pos >= p_len) { parseFrame(); p_state = 0; }
      break;
    default: p_state = 0; break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Radar.begin(256000, SERIAL_8N1, RADAR_RX_PIN, RADAR_TX_PIN);
  Tts.begin(9600, SERIAL_8N1, TTS_RX_PIN, TTS_TX_PIN);
  Serial.println();
  Serial.println("慧药管家 · 阶段1 自检");
  Serial.println("人走近 1.5 米内应听到播报；串口输入 t 可手动测试播报");
}

void loop() {
  while (Radar.available()) {
    radar_bytes++;
    feed(Radar.read());
  }

  if (present && millis() - last_seen > PRESENCE_MS) {
    present = false;
    Serial.println("[RADAR] timeout -> none");
  }

  if (millis() - last_radar_report >= 5000) {
    last_radar_report = millis();
    Serial.printf("[RADAR] bytes=%lu frames=%lu\n", radar_bytes, radar_frames);
  }

  if (Serial.available()) {
    char c = (char)Serial.read();
    if (c == 't' || c == 'T') {
      Serial.println("[TEST] manual speak");
      speakGb2312(PHRASE, sizeof(PHRASE));
    }
  }
}
