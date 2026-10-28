# 慧药管家 · 硬件开发

当前阶段：**阶段 0–1（到货自检 + 雷达与播报联调）**

目标：不联网、不接服务器、不接摄像头，只验证“人走近 → 喇叭念出中文”。

---

## 一、目录

```
hardware/
├── esp32c3/
│   └── radar_tts_test/
│       └── radar_tts_test.ino    # 阶段1自检固件
├── tools/
│   └── gb2312_hex.py             # 中文转 SYN6288 编码
└── README.md
```

---

## 二、接线

ESP32-C3 SuperMini 引脚：

| 模块 | 模块引脚 | 接到 ESP32-C3 | 说明 |
|---|---|---|---|
| LD2410C | VCC | **5V** | 不要接 3.3V |
| LD2410C | GND | GND | 必须共地 |
| LD2410C | TX | GPIO20 | 雷达发，板子收 |
| LD2410C | RX | GPIO21 | 板子发，雷达收 |
| LD2410C | OUT | 不接 | 本方案用串口，不用电平输出 |
| SYN6288 | VCC | **5V** | 与雷达共用 5V |
| SYN6288 | GND | GND | 共地 |
| SYN6288 | RXD | GPIO7 | 只接这一根信号线 |
| SYN6288 | TXD | 不接 | 不需要回读 |
| 小喇叭 | SPK+ / SPK- | SYN6288 的 SPK+ / SPK- | 不分正负 |

```
        ┌───────────────┐
 5V ────┤ 5V        GND ├──── GND
        │               │
        │  ESP32-C3     │
        │   SuperMini   │
        │               │
 GPIO20 ├── RX     TX ──┤ GPIO21
 GPIO7  ├── TX          │
        └───────┬───────┘
                │ USB-C 供电 + 烧录
```

**上电前用万用表确认：模块 VCC 与 GND 之间是 5V，不是 3.3V，也不是反的。**

---

## 三、环境准备

1. 安装 Arduino IDE 2.x。
2. 打开「文件 → 首选项 → 附加开发板管理器网址」，加入：
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`
3. 「开发板管理器」搜索 `esp32`，安装 Espressif Systems 的 ESP32 包（3.x）。
4. 开发板选择 **ESP32C3 Dev Module**。
5. 在「工具」里设置：
   - USB CDC On Boot：**Enabled**（否则串口监视器看不到输出）
   - Flash Size：4MB
   - Partition Scheme：Default 4MB with spiffs
   - Upload Speed：921600（如果失败改成 115200）
6. 打开 `hardware/esp32c3/radar_tts_test/radar_tts_test.ino` 并上传。

> 上传时如果提示 `Connecting...` 卡住：按住板子上的 BOOT 键，点上传，出现 `Connecting` 后松开。

---

## 四、第一次上电

1. 只插 USB 线，先打开串口监视器（115200）。
2. 应看到：
   ```
   慧药管家 · 阶段1 自检
   人走近 1.5 米内应听到播报；串口输入 t 可手动测试播报
   ```
3. 在串口输入框输入 `t` 回车，喇叭应念出「检测到有人，请按时服药。」
   - 这一条不通，先别测雷达，检查 SYN6288 的 5V、GND、RXD→GPIO7。
4. 用手在雷达前方晃动，串口应出现：
   ```
   [RADAR] target=1 detect=85cm moving=85cm static=0cm
   [TRIGGER] speak
   ```
5. 手离开 3 秒后应出现 `[RADAR] timeout -> none`。

---

## 五、验收标准

- [ ] 串口输入 `t` 能出声
- [ ] 手在 1.5 米内晃动，串口有 `target` 输出
- [ ] 走近时自动播报一次
- [ ] 30 秒内不重复播报
- [ ] 手离开后状态回到 `none`

---

## 六、常见问题

**串口一片空白**
- USB CDC On Boot 没开；或用了只能充电的线。

**上传失败 / 找不到端口**
- 换一根能传数据的 Type-C 线；装 CP210x/CH343 驱动；按住 BOOT 再上传。

**雷达没有任何输出**
- 波特率必须是 256000；TX/RX 要交叉；VCC 必须 5V。
- 用手机装「HLKRadarTool」蓝牙连模块，能搜到说明模块是好的。

**雷达一直显示有人**
- 灵敏度太高。用 HLKRadarTool 下调各距离门灵敏度，或调整安装角度避开墙面。

**喇叭没声音**
- 先量 SYN6288 的 VCC 是否为 5V；再看 RXD 是否接到 GPIO7。
- 如果串口打印了 `[TTS] sent` 但没声音，多半是供电不足或喇叭线没接好。

**有声音但是杂音/断续**
- 换 5V/2A 以上的电源；缩短杜邦线；确认共地。

---

## 七、换成自己的播报内容

SYN6288 只认 GB2312/GBK，不能直接发 UTF-8 中文。用工具生成字节数组：

```bash
python tools/gb2312_hex.py "该吃九九九感冒灵，一次一袋。"
```

把输出的 `PHRASE[]` 替换进 `.ino` 重新上传即可。

---

## 八、下一步

阶段 1 通过后，进入阶段 2：

1. 给 ESP32-C3 加 WiFi，开机连网。
2. 增加一个后端接口，返回当天要播报的文本。
3. 固件把雷达事件上报后端，后端返回文本，再交给 SYN6288。
4. 同时开始给香橙派刷 Armbian、接 USB 摄像头。

---
## 九、香橙派摄像头自检（拿到板子后）

香橙派刷好 Armbian 后，把 USB 摄像头插上，运行：

```bash
python3 camera_probe.py
```

它会打印分辨率、帧率和编码格式，并保存 snapshot.jpg 与 	est.mp4。

- 输出里有 MJPG 和 1920x1080：合格
- 输出是 YUY2：把分辨率降到 1280x720
- 打不开 /dev/video0：先 ls -l /dev/video*，检查是不是插在 USB-A 口


## 十、香橙派摄像头与 App 联动

摄像头相关文件：

```text
hardware/pi/device_agent_client.py      常驻代理，主动轮询后端
hardware/pi/deploy_device_agent.py      一键部署脚本
hardware/vision/camera_snapshot.py      远程抓拍
hardware/vision/intake_recorder.py      无音频服药录像 + 缩略图
```

部署命令见 `docs/摄像头服务部署与验证.md`。正式运行时，香橙派应使用独立 5V/3A 电源，不依赖电脑 USB；代理会主动连接后端，因此家庭路由器不需要开放入站端口。

App 当前提供远程单张抓拍、20 秒录像、缩略图、视频播放和家属确认。实时直播不在这一版范围内，后续应使用 WebRTC 出站连接。
## 十一、ESP32-C3 联网节点

联网固件位于 `hardware/esp32c3/smart_box_node/`。它会直接向后端上报雷达事件、领取个人用药播报文本、接收小智打断信号并控制 SYN6288。

电脑侧联调、WebSocket 接口和小智状态回调见 `docs/联网设备与播报联动.md`。