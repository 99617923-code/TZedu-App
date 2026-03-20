/// 途正英语 - IM 服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. SDK 延迟初始化（进入聊天页面或登录成功后触发）
/// 2. 按平台选择 NIMAndroidSDKOptions / NIMIOSSDKOptions / NIMWebSDKOptions
/// 3. 登录/登出（accid + token 由后端下发）
/// 4. 连接状态管理与监听
/// 5. 全局单例，供各页面调用
///
/// 使用方式：
///   await IMService.instance.ensureInitialized(); // 延迟初始化
///   await IMService.instance.login(accid, token);
///
/// 注意：用户体系完全自建，此处只负责 IM SDK 的登录，
/// 不涉及业务用户注册/登录逻辑。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../config/im_config.dart';

// 条件导入：Web 端不支持 dart:io
import 'platform_helper_stub.dart'
    if (dart.library.io) 'platform_helper_io.dart' as platform;

/// IM 连接状态枚举
enum IMConnectionStatus {
  disconnected,
  connecting,
  connected,
  loggedIn,
  kicked,
  tokenExpired,
}

class IMService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final IMService _instance = IMService._internal();
  static IMService get instance => _instance;
  IMService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isInitializing = false;

  IMConnectionStatus _connectionStatus = IMConnectionStatus.disconnected;
  IMConnectionStatus get connectionStatus => _connectionStatus;

  String? _currentAccid;
  String? get currentAccid => _currentAccid;

  bool get isLoggedIn => _connectionStatus == IMConnectionStatus.loggedIn;

  /// 初始化失败的错误信息（用于 UI 展示）
  String? _initError;
  String? get initError => _initError;

  /// 连接状态变化流（供 UI 监听）
  final StreamController<IMConnectionStatus> _statusController =
      StreamController<IMConnectionStatus>.broadcast();
  Stream<IMConnectionStatus> get statusStream => _statusController.stream;

  /// 被踢出事件流
  final StreamController<String> _kickedController =
      StreamController<String>.broadcast();
  Stream<String> get kickedStream => _kickedController.stream;

  // Stream 订阅
  StreamSubscription<NIMLoginStatus>? _loginStatusSub;
  StreamSubscription<dynamic>? _loginFailedSub;
  StreamSubscription<NIMKickedOfflineDetail>? _kickedSub;
  StreamSubscription<NIMConnectStatus>? _connectStatusSub;

  // ═══════════════════════════════════════════════════════
  // 延迟初始化
  // ═══════════════════════════════════════════════════════

  /// 确保 SDK 已初始化（延迟加载，首次调用时才初始化）
  /// 在进入聊天页面或登录成功后调用
  Future<bool> ensureInitialized() async {
    if (_isInitialized) return true;
    if (_isInitializing) {
      // 等待正在进行的初始化完成
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    return initialize();
  }

  /// 初始化网易云信 SDK（内部方法）
  Future<bool> initialize() async {
    if (_isInitialized) {
      _log('SDK 已初始化，跳过');
      return true;
    }

    _isInitializing = true;
    _initError = null;

    try {
      _log('开始初始化网易云信 SDK...');

      // 按平台构建 SDK 配置
      final options = _buildSDKOptions();
      if (options == null) {
        _log('当前平台不支持 IM SDK');
        _initError = '当前平台不支持 IM';
        _isInitializing = false;
        return false;
      }

      // 初始化 SDK
      final result = await NimCore.instance.initialize(options);

      if (result.isSuccess) {
        _isInitialized = true;
        _initError = null;
        _log('SDK 初始化成功');

        // 注册监听器
        _setupListeners();

        _isInitializing = false;
        notifyListeners();
        return true;
      } else {
        _initError = 'SDK 初始化失败: ${result.errorDetails}';
        _log(_initError!);
        _isInitializing = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _initError = 'SDK 初始化异常: $e';
      _log(_initError!);
      _isInitializing = false;
      notifyListeners();
      return false;
    }
  }

  /// 按平台构建 SDK 配置
  NIMSDKOptions? _buildSDKOptions() {
    if (kIsWeb) {
      return NIMWebSDKOptions(
        appKey: IMConfig.appKey,
        initializeOptions: NIMInitializeOptions(
          appkey: IMConfig.appKey,
          apiVersion: 'v2',
        ),
      );
    }

    // 非 Web 端使用条件导入的平台检测
    return platform.buildNativeSDKOptions(IMConfig.appKey);
  }

  // ═══════════════════════════════════════════════════════
  // 登录/登出
  // ═══════════════════════════════════════════════════════

  /// 登录 IM
  /// [accid] 网易云信账号 ID（由后端在用户登录时返回）
  /// [token] IM Token（由后端在用户登录时返回）
  Future<bool> login(String accid, String token) async {
    // 确保 SDK 已初始化
    final initialized = await ensureInitialized();
    if (!initialized) {
      _log('SDK 未初始化，无法登录');
      return false;
    }

    try {
      _updateStatus(IMConnectionStatus.connecting);
      _log('正在登录 IM，accid: $accid');

      final loginOption = NIMLoginOption();

      final result = await NimCore.instance.loginService.login(
        accid,
        token,
        loginOption,
      );

      if (result.isSuccess) {
        _currentAccid = accid;
        _updateStatus(IMConnectionStatus.loggedIn);
        _log('IM 登录成功');
        return true;
      } else {
        _updateStatus(IMConnectionStatus.disconnected);
        _log('IM 登录失败: ${result.errorDetails}');
        return false;
      }
    } catch (e) {
      _updateStatus(IMConnectionStatus.disconnected);
      _log('IM 登录异常: $e');
      return false;
    }
  }

  /// 登出 IM
  Future<void> logout() async {
    if (!_isInitialized) return;

    try {
      _log('正在登出 IM...');
      await NimCore.instance.loginService.logout();
      _currentAccid = null;
      _updateStatus(IMConnectionStatus.disconnected);
      _log('IM 已登出');
    } catch (e) {
      _log('IM 登出异常: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 监听器（使用 Stream 方式）
  // ═══════════════════════════════════════════════════════

  /// 注册 SDK 事件监听
  void _setupListeners() {
    final loginService = NimCore.instance.loginService;

    // 登录状态监听
    _loginStatusSub = loginService.onLoginStatus.listen((status) {
      _log('登录状态变化: $status');
      switch (status) {
        case NIMLoginStatus.loginStatusLogined:
          _updateStatus(IMConnectionStatus.loggedIn);
          break;
        case NIMLoginStatus.loginStatusLogout:
          _updateStatus(IMConnectionStatus.disconnected);
          break;
        case NIMLoginStatus.loginStatusLogining:
          _updateStatus(IMConnectionStatus.connecting);
          break;
        default:
          break;
      }
    });

    // 登录失败监听
    _loginFailedSub = loginService.onLoginFailed.listen((error) {
      _log('登录失败回调: ${error.code} ${error.desc}');
      _updateStatus(IMConnectionStatus.disconnected);
    });

    // 被踢下线监听
    _kickedSub = loginService.onKickedOffline.listen((detail) {
      _log('被踢下线');
      _currentAccid = null;
      _updateStatus(IMConnectionStatus.kicked);
      _kickedController.add('您的账号在其他设备登录');
    });

    // 连接状态监听
    _connectStatusSub = loginService.onConnectStatus.listen((status) {
      _log('连接状态变化: $status');
      switch (status) {
        case NIMConnectStatus.nimConnectStatusConnected:
          _updateStatus(IMConnectionStatus.connected);
          break;
        case NIMConnectStatus.nimConnectStatusDisconnected:
          if (_connectionStatus != IMConnectionStatus.kicked) {
            _updateStatus(IMConnectionStatus.disconnected);
          }
          break;
        case NIMConnectStatus.nimConnectStatusConnecting:
          _updateStatus(IMConnectionStatus.connecting);
          break;
        case NIMConnectStatus.nimConnectStatusWaiting:
          _updateStatus(IMConnectionStatus.connecting);
          break;
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════

  void _updateStatus(IMConnectionStatus status) {
    if (_connectionStatus != status) {
      _connectionStatus = status;
      _statusController.add(status);
      notifyListeners();
    }
  }

  void _log(String message) {
    if (IMConfig.enableDebugLog) {
      debugPrint('[IMService] $message');
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _loginStatusSub?.cancel();
    _loginFailedSub?.cancel();
    _kickedSub?.cancel();
    _connectStatusSub?.cancel();
    _statusController.close();
    _kickedController.close();
    super.dispose();
  }
}
