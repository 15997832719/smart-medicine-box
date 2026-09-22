# 慧药管家 - Flutter 前端

> 面向 Android 的适老化智能药箱 APP

## 环境要求

- Flutter SDK ≥ 3.0
- Dart ≥ 3.0
- Android SDK（Flutter 开发）

## 快速开始

```bash
# 进入前端目录
cd flutter_app

# 安装依赖
flutter pub get

# 运行开发版本（连接手机或模拟器）
flutter run

# 打包 Debug APK
flutter build apk --debug

# 打包 Release APK
flutter build apk --release
```

## 目录结构

```
flutter_app/
├── lib/
│   ├── main.dart                 # APP 入口
│   │
│   ├── core/                    # 核心配置
│   │   ├── config.dart          # API 地址配置
│   │   ├── theme.dart           # 适老化主题配置
│   │   └── auth_service.dart    # 认证状态管理
│   │
│   ├── models/                  # 数据模型
│   │   └── medicine.dart        # 药品、计划、记录模型
│   │
│   ├── services/                # API 服务
│   │   └── api_service.dart     # HTTP 请求封装
│   │
│   ├── screens/                 # 页面
│   │   ├── auth/
│   │   │   └── login_screen.dart    # 登录/注册
│   │   ├── elder/
│   │   │   └── elder_home_screen.dart # 老人端首页
│   │   └── child/
│   │       └── child_home_screen.dart  # 子女端首页
│   │
│   └── widgets/                  # 通用组件
│
├── pubspec.yaml                 # 依赖配置
└── README.md
```

## 适老化设计规范

已在 `core/theme.dart` 中统一配置：

- 基础字号：**18px**（比标准大）
- 标题字号：**24px**
- 按钮高度：**60px**（方便老人点击）
- 图标大小：**32px**
- 高对比度配色
- 大间距、大触控区域

## API 对接

开发阶段 APP 默认访问 `http://10.0.2.2:8000`（Android 模拟器访问本地电脑）。

**修改为你的服务器 IP：**
编辑 `lib/core/config.dart`，将 `baseUrl` 改为实际地址。

## 状态管理

使用 `provider` 进行状态管理，`AuthService` 管理登录状态。

## 注意事项

- 首次运行需要申请相机、麦克风和通知权限
- 语音识别使用手机系统的中文识别服务，不依赖项目自建 ASR
- 如果手机没有中文语音识别引擎或用户拒绝权限，语音助手会显示原因、提供重新授权入口，并保留文字输入兜底
- 语音播报使用系统 TTS；设备没有中文语音包时，文字回复仍可正常使用
