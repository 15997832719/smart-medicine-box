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

## 人脸刷脸登录（A 版：实时预览 + 圆框引导 + 自动抓拍）

Flutter 侧不再使用系统相机拍照，鸿蒙改为原生实时相机：

- 原生页面：`entry/src/main/ets/pages/FaceCameraPage.ets`
- 会话桥：`entry/src/main/ets/facecamera/FaceCameraSession.ets`
- 通道：`smart_medicine_box/face_camera`（`isAvailable` / `capture`），在 `EntryAbility.ets` 注册
- Flutter 调用：`frontend/lib/services/face_camera_service.dart`（`FaceCameraService.takeFacePhoto`）
- 接入界面：`frontend/lib/screens/auth/face_login_screen.dart`、`face_enroll_screen.dart`

流程：前置摄像头预览 -> 圆形引导框「请把脸放进圆框」-> 2 秒倒计时 -> 自动抓拍 ->
返回 JPEG 给 Flutter -> `/api/v1/face/login` 或 `/api/v1/face/enroll` 由腾讯云 1:N 比对。

说明与限制：

- A 版没有眨眼/张嘴活体检测，无法防照片攻击，后续可加。
- 抓拍结果写入应用 cache 目录，Flutter 读取后立即删除临时文件。
- 权限被拒、相机不可用、原生页面打不开时，Flutter 自动回退到原来的系统拍照。
- Android / iOS 未实现该通道，`isAvailable` 返回 false，行为与以前一致。

需要新增的权限（已配置在 `module.json5`）：

- `ohos.permission.CAMERA`（reason: `$string:camera_reason`）

## 构建与签名 HAP

```powershell
$env:DEVECO_SDK_HOME='D:\HarmonyOS\sdk'
$env:NODE_PATH='D:\HarmonyOS\hvigor-6.21.2\node_modules'
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot'
$env:OHOS_BASE_SDK_HOME='D:\HarmonyOS\sdk'
$env:PATH='D:\HarmonyOS\flutter_flutter\bin;D:\HarmonyOS\tools\ohpm\bin;D:\HarmonyOS\tools\node;D:\soft\nodejs;D:\HarmonyOS\tools\bin;' + $env:PATH

cd D:\smart-medicine-box\frontend
flutter build hap --release    # 会生成 AOT 资源，但缺少 Signing Configs 时签名步骤会失败

# 只改了 ArkTS 代码时，可以跳过 flutter 直接重新打包（必须带 buildMode=release，
# 否则会打出 debug 版：体积更大并带 sourceMap）
cd D:\smart-medicine-box\frontend\ohos
node "D:\HarmonyOS\hvigor-6.21.2\node_modules\@ohos\hvigor\bin\hvigor.js" `
  -p product=default -p buildMode=release assembleHap --no-daemon

# 手动签名（OpenHarmony 默认发布证书）
java -jar D:\HarmonyOS\sdk\windows\toolchains\lib\hap-sign-tool.jar sign-app `
  -keyAlias "openharmony application release" -signAlg "SHA256withECDSA" -mode "localSign" `
  -appCertFile "D:\HarmonyOS\signing\app-release-chain.cer" `
  -profileFile "D:\HarmonyOS\signing\smart-medicine-profile.p7b" `
  -inFile "D:\smart-medicine-box\frontend\ohos\entry\build\default\outputs\default\entry-default-unsigned.hap" `
  -outFile "D:\smart-medicine-box\dist\smart-medicine-box-harmonyos.hap" `
  -keystoreFile "D:\HarmonyOS\sdk\windows\toolchains\lib\OpenHarmony.p12" `
  -keyPwd "123456" -keystorePwd "123456"
```