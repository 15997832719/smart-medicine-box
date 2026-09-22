# 智能药箱 HarmonyOS 提醒工程

本目录是使用 OpenHarmony Flutter 官方模板生成的 HarmonyOS 宿主工程，原有 Android、iOS 和 Flutter 代码均保留。

## 已接入功能

- 使用 `reminderAgentManager` 创建系统提醒代理。
- 支持每日服药提醒、稍后提醒、关闭提醒和点击打开应用。
- 提醒由 HarmonyOS 系统管理，不依赖 Android 兼容层的 `SCHEDULE_EXACT_ALARM`。
- Flutter 侧通过 `smart_medicine_box/reminders` MethodChannel 同步计划。
- 首次使用时会请求通知权限。

## 构建环境

需要安装：

- DevEco Studio，建议使用支持 HarmonyOS 6 的版本。
- HarmonyOS SDK，API 12 或更高版本。
- OpenHarmony Flutter 适配版 SDK，不要使用标准 Flutter SDK。

OpenHarmony Flutter SDK 地址：

```text
https://gitcode.com/openharmony-sig/flutter_flutter
```

按该仓库 README 配置以下环境变量：

```powershell
$env:TOOL_HOME = "D:\DevEco Studio"
$env:DEVECO_SDK_HOME = "$env:TOOL_HOME\sdk"
$env:PATH = "$env:TOOL_HOME\tools\ohpm\bin;$env:PATH"
$env:PATH = "$env:TOOL_HOME\tools\hvigor\bin;$env:PATH"
$env:PATH = "$env:TOOL_HOME\tools\node;$env:PATH"
$env:PATH = "<flutter_flutter>\bin;$env:PATH"
```

## 生成并构建 HAP

在 `D:\smart-medicine-box\frontend` 目录执行：

```powershell
flutter pub get
flutter build hap --release
```

构建成功后的文件通常位于：

```text
D:\smart-medicine-box\frontend\ohos\entry\build\default\outputs\default\entry-default-signed.hap
```

`har/flutter.har`、插件注册文件、Flutter assets 和 native 动态库由 OpenHarmony Flutter 构建过程生成，不应手工维护。

## 权限

`entry/src/main/module.json5` 已声明：

- `ohos.permission.INTERNET`
- `ohos.permission.PUBLISH_AGENT_REMINDER`

首次发布提醒前，应用会调用：

`notificationManager.requestEnableNotification`

用户需要允许通知。若通知被关闭，提醒代理会返回 `1700001`。
