/// 途正英语 - 内置版本历史数据
/// 火鹰科技出品
///
/// 每次发版时更新此文件，App 离线也能查看完整版本历史
/// 后端可通过 API 拉取此数据进行存储管理
///
/// 更新规则：
/// 1. 每次发布新版本时，在 versions 列表顶部添加新版本记录
/// 2. version 字段使用语义化版本号（major.minor.patch）
/// 3. changes 中的 category 可选值: feat / fix / improve / docs / chore
/// 4. module 字段标注影响的模块，便于后台筛选

import '../models/app_version.dart';

/// 完整版本历史（按时间倒序，最新版本在最前面）
const List<AppVersion> appVersionHistory = [
  // ═══════════════════════════════════════════════════════
  // v1.3.0 — 2026-03-22
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.3.0',
    buildNumber: '8',
    type: 'minor',
    releaseDate: '2026-03-22',
    title: '全面补全 IM 聊天功能',
    description: '修复 Mock 模式闪现问题，补全消息长按菜单、图片/视频/文件发送、消息撤回/删除/转发、会话免打扰等完整聊天能力。',
    commitHash: 'd536c8f',
    changes: [
      ChangelogEntry(category: 'fix', content: '修复会话列表每次打开闪现 Mock 原型数据的问题', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增消息长按菜单：复制、转发、撤回（2分钟内）、删除', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增图片选择发送（相册/拍照）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增视频选择发送', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增文件选择发送', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增附件面板（+号展开：相册/拍照/视频/文件）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增视频消息气泡（封面+播放按钮+时长）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增文件消息气泡（文件图标+文件名+大小）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增图片全屏预览（支持缩放）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增消息搜索对话框', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增聊天设置面板（搜索/清空/免打扰）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增发送失败重发功能', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '新增会话免打扰功能', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '文本消息支持长按选择复制', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '输入框支持多行输入（最多4行）', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '撤回消息显示为系统提示', module: '聊天'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.2.1 — 2026-03-22
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.2.1',
    buildNumber: '7',
    type: 'patch',
    releaseDate: '2026-03-22',
    title: '修复 Android 聊天三大问题',
    description: '修复会话列表重启后空白、推送消息不显示、导航图标无未读红点三个核心问题。',
    commitHash: 'ba1bc3a',
    changes: [
      ChangelogEntry(category: 'fix', content: '修复会话列表重启后空白（增加本地缓存机制）', module: '聊天'),
      ChangelogEntry(category: 'fix', content: '修复推送消息在会话列表不显示', module: '聊天'),
      ChangelogEntry(category: 'fix', content: '修复导航图标无未读红点', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '增加 IM 重连后自动刷新会话列表', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '增加 App 生命周期管理（后台恢复自动刷新）', module: '聊天'),
      ChangelogEntry(category: 'improve', content: '未读数持久化到本地存储', module: '聊天'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.2.0 — 2026-03-21
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.2.0',
    buildNumber: '6',
    type: 'minor',
    releaseDate: '2026-03-21',
    title: 'IM 消息收发稳定性全面修复',
    description: '修复 iOS 模拟器编译、消息收发失败、应用内通知等多个关键问题，大幅提升 IM 稳定性。',
    commitHash: '64f4828',
    changes: [
      ChangelogEntry(category: 'fix', content: '三重修复 iOS 26 模拟器 arm64 兼容性问题', module: 'iOS'),
      ChangelogEntry(category: 'fix', content: 'arm64-to-sim 自动修复 YXAlog SDK', module: 'iOS'),
      ChangelogEntry(category: 'fix', content: '修复 API 方法名拼写错误（sendP2PMessageReceipt）', module: 'IM'),
      ChangelogEntry(category: 'fix', content: '修复消息收发和通知的核心问题', module: 'IM'),
      ChangelogEntry(category: 'fix', content: '修复消息收发失败（IM 连接状态判断优化）', module: 'IM'),
      ChangelogEntry(category: 'feat', content: '新增应用内消息横幅通知（带动画+提示音）', module: '通知'),
      ChangelogEntry(category: 'fix', content: '修复所有平台会话列表为空的问题', module: '聊天'),
      ChangelogEntry(category: 'fix', content: '修复 iOS 模拟器构建失败', module: 'iOS'),
      ChangelogEntry(category: 'improve', content: '桌面端新增本地会话管理系统', module: '聊天'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.1.0 — 2026-03-20
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.1.0',
    buildNumber: '5',
    type: 'minor',
    releaseDate: '2026-03-20',
    title: '开发工具链 + 聊天功能增强',
    description: '新增 SwiftUI 原生开发启动器、手机号搜索发起聊天、多平台编译修复。',
    commitHash: 'cd14eef',
    changes: [
      ChangelogEntry(category: 'feat', content: '重写开发启动器为 SwiftUI 原生应用', module: '工具'),
      ChangelogEntry(category: 'feat', content: '启动器增加「更新启动器」按钮', module: '工具'),
      ChangelogEntry(category: 'feat', content: '添加一键开发自动化脚本（三端启动/停止/状态）', module: '工具'),
      ChangelogEntry(category: 'feat', content: '加号按钮改为手机号搜索用户发起聊天', module: '聊天'),
      ChangelogEntry(category: 'fix', content: 'macOS 桌面端完全跳过 NIM ConversationService 原生调用', module: 'macOS'),
      ChangelogEntry(category: 'fix', content: '等待 NIM SDK 数据同步完成后再调用会话列表', module: 'IM'),
      ChangelogEntry(category: 'fix', content: '防止 NIM SDK 未初始化时调用导致 macOS 崩溃', module: 'macOS'),
      ChangelogEntry(category: 'fix', content: '修复 CocoaPods xcconfig 集成问题', module: 'iOS/macOS'),
      ChangelogEntry(category: 'fix', content: '修复多平台编译运行问题', module: '全平台'),
      ChangelogEntry(category: 'fix', content: '添加 iOS/macOS Podfile 和一键配置脚本', module: 'iOS/macOS'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.0.2 — 2026-03-20
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.0.2',
    buildNumber: '4',
    type: 'patch',
    releaseDate: '2026-03-20',
    title: '前端功能强化',
    description: '新增 AI 分级测评完整流程、编辑资料页面、设备管理服务，强化登录和个人中心。',
    commitHash: '59fcfd0',
    changes: [
      ChangelogEntry(category: 'feat', content: 'AI 分级测评页面（完整测评流程 UI，自适应难度）', module: '测评'),
      ChangelogEntry(category: 'feat', content: '测评结果页面（四维评估展示、学习建议）', module: '测评'),
      ChangelogEntry(category: 'feat', content: '测评历史页面（分页历史记录列表）', module: '测评'),
      ChangelogEntry(category: 'feat', content: '编辑资料页面（昵称/头像修改，自动同步 IM）', module: '个人中心'),
      ChangelogEntry(category: 'feat', content: '测评服务层（封装全部 8 个测评 API）', module: '测评'),
      ChangelogEntry(category: 'feat', content: '设备管理服务层（注册/心跳/推送Token/下线）', module: '设备'),
      ChangelogEntry(category: 'feat', content: '登录页面（密码登录+短信验证码登录）', module: '认证'),
      ChangelogEntry(category: 'feat', content: '个人中心页面（用户信息卡片+功能菜单）', module: '个人中心'),
      ChangelogEntry(category: 'feat', content: '认证网关（未登录自动跳转登录页）', module: '认证'),
      ChangelogEntry(category: 'fix', content: '适配后端正式 API（refreshToken/AppKey 动态获取）', module: 'API'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.0.1 — 2026-03-18
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.0.1',
    buildNumber: '3',
    type: 'patch',
    releaseDate: '2026-03-18',
    title: '集成网易云信 IM SDK',
    description: '集成 nim_core_v2 SDK，创建完整 IM 服务层，实现聊天模块原型设计还原。',
    commitHash: '8d25e19',
    changes: [
      ChangelogEntry(category: 'feat', content: '集成 nim_core_v2 SDK', module: 'IM'),
      ChangelogEntry(category: 'feat', content: '创建 IMService（SDK 初始化、登录/登出、连接状态管理）', module: 'IM'),
      ChangelogEntry(category: 'feat', content: '创建 TZConversationService（会话列表管理）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '创建 ChatMessageService（消息收发、历史消息）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '创建 UserInfoService（用户资料查询与缓存）', module: 'IM'),
      ChangelogEntry(category: 'feat', content: '创建 AuthService（对接自建后端登录接口）', module: '认证'),
      ChangelogEntry(category: 'feat', content: '聊天模块完全还原原型设计（6种聊天类型）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '聊天列表页面（筛选标签、搜索、卡片）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '聊天面板（消息列表、AI教练评分、输入栏）', module: '聊天'),
      ChangelogEntry(category: 'feat', content: '桌面端微信风格左右分栏布局', module: 'UI'),
      ChangelogEntry(category: 'fix', content: '彻底修复 iOS 滚动问题', module: 'iOS'),
    ],
  ),

  // ═══════════════════════════════════════════════════════
  // v1.0.0 — 2026-03-18
  // ═══════════════════════════════════════════════════════
  AppVersion(
    version: '1.0.0',
    buildNumber: '1',
    type: 'major',
    releaseDate: '2026-03-18',
    title: '途正英语 v1.0.0 首版发布',
    description: '完美还原原型首页设计，支持学生/老师/家长三端角色切换，在线更新检查，响应式多端适配。',
    commitHash: '730878f',
    changes: [
      ChangelogEntry(category: 'feat', content: '完美还原原型首页设计（学生/老师/家长三端）', module: '首页'),
      ChangelogEntry(category: 'feat', content: 'Hero Banner + 功能大图卡片 + 快捷入口', module: '首页'),
      ChangelogEntry(category: 'feat', content: '角色切换动画', module: '首页'),
      ChangelogEntry(category: 'feat', content: '在线更新检查功能（基于 GitHub Releases）', module: '更新'),
      ChangelogEntry(category: 'feat', content: '响应式布局（手机/平板/桌面）', module: 'UI'),
      ChangelogEntry(category: 'feat', content: 'macOS 网络权限配置', module: 'macOS'),
      ChangelogEntry(category: 'feat', content: 'GitHub Actions CI/CD（Windows .exe + Web）', module: 'CI/CD'),
      ChangelogEntry(category: 'feat', content: '移动端5Tab底部导航（消息/学习/商城/直播/我的）', module: 'UI'),
      ChangelogEntry(category: 'feat', content: '桌面端竖向图标侧边导航栏', module: 'UI'),
    ],
  ),
];
