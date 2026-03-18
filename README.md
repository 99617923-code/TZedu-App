# 途正英语 - 智慧教学管理系统

> Flutter 多端版本 · 一套代码支持 iOS / Android / macOS / Windows / Web

## 项目概述

途正英语智慧教学管理系统是一款面向雅思教育培训的全平台应用，支持学生、老师、家长三种角色，提供课程管理、作业批改、外教直播、AI辅助等核心功能。

## 技术架构

| 技术栈 | 说明 |
|--------|------|
| Flutter 3.29.2 | 跨平台 UI 框架 |
| Dart 3.7.2 | 编程语言 |
| 自建 OAuth 2.0 | 用户认证（零平台依赖） |
| 网易云信 NERTC | 音视频 SDK |
| GitHub Actions | CI/CD 自动构建 |

## 支持平台

- iOS 12.0+
- Android 5.0+ (API 21+)
- macOS 10.14+
- Windows 10+
- Web (Chrome, Safari, Firefox, Edge)

## 快速开始

### 环境要求

- Flutter 3.29.2+
- Xcode 16+ (macOS/iOS)
- Android Studio 2024+ (Android)
- CocoaPods (macOS/iOS)

### 运行项目

```bash
# 克隆项目
git clone https://github.com/99617923-code/TZedu-App.git
cd TZedu-App

# 安装依赖
flutter pub get

# 运行各平台
flutter run -d ios
flutter run -d android
flutter run -d macos
flutter run -d windows
flutter run -d chrome
```

### 构建发布版

```bash
flutter build ios --release
flutter build apk --release
flutter build macos --release
flutter build windows --release
flutter build web --release
```

## 项目结构

```
lib/
├── main.dart              # 应用入口
├── config/
│   ├── theme.dart         # 主题配置
│   └── constants.dart     # 常量配置
├── models/
│   ├── app_role.dart      # 角色模型
│   └── home_data.dart     # 首页数据模型
├── pages/
│   └── home_page.dart     # 首页
├── widgets/
│   ├── feature_card.dart  # 功能大图卡片
│   ├── quick_entry.dart   # 快捷入口
│   ├── role_switcher.dart # 角色切换
│   └── hero_banner.dart   # Hero Banner
├── services/
│   └── update_service.dart # 在线更新服务
└── utils/
    └── responsive.dart    # 响应式布局工具
```

## CI/CD

- **Windows .exe 构建**: 推送 `v*` 标签自动触发 GitHub Actions 构建
- **Web 构建**: 推送到 `main` 分支自动触发构建

## 在线更新

应用内置在线更新检查功能，支持：
- 启动时自动检查更新
- 手动检查更新（首页底部按钮）
- 强制更新提示
- 多平台差异化更新（App Store / APK / 安装包）

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0.0 | 2026-03-18 | 首页 UI + 在线更新 + 多端适配 |

---

**开发团队**: 火鹰科技
**联系邮箱**: ceo@figo.cn
**官网**: www.figo.cn
