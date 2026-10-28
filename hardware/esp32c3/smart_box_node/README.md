# ESP32-C3 联网节点

## 依赖

Arduino IDE 安装：

- Espressif ESP32 开发板包 3.x
- ArduinoJson 7.x（库管理器搜索 ArduinoJson）
- ESP32 开发板选择：`ESP32C3 Dev Module`

## 配置

把 `secrets.h.example` 复制为 `secrets.h`，填写：

- WiFi 名称和密码
- 后端地址
- 设备标识，例如 `orangepi-001`
- 与后端一致的 `SMB_DEVICE_AGENT_TOKEN`

## 接线

| 模块 | 引脚 | ESP32-C3 |
|---|---|---|
| LD2410C | VCC/GND | 5V/GND |
| LD2410C | TX | GPIO20 |
| LD2410C | RX | GPIO21 |
| SYN6288 | VCC/GND | 5V/GND |
| SYN6288 | RXD | GPIO7 |
| SYN6288 | TXD | 不接 |
| 喇叭 | SPK+ / SPK- | SYN6288 对应引脚 |

## 功能

- 检测到人进入时上报后端。
- 每 1 秒读取小智/SYN6288 运行状态。
- 小智进入聆听或说话时，ESP32 立即发送 SYN6288 停止帧。
- 每 1.5 秒尝试领取一条播报；后端返回 GB2312 Base64，ESP32 直接送入 SYN6288。
- 网络断开时仍可在串口输入 `t` 做本地 SYN6288 测试，输入 `s` 停止。

## 验证

1. 串口应出现 `ESP32-C3 node ready`。
2. 手机热点/路由器给 ESP32 分配网络后，应能访问后端。
3. App 下发“测试识别”或雷达触发后，后端产生播报事件。
4. ESP32 串口出现 `[TTS] speaking`。
5. 让另一个客户端调用 `POST /api/v1/device-agent/xiaozhi/state`，state 为 `listening`，ESP32 应停止播报。