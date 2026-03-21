/// 途正英语 - IM 服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. SDK 延迟初始化（进入聊天页面或登录成功后触发）
/// 2. 按平台选择 NIMAndroidSDKOptions / NIMIOSSDKOptions / NIMWebSDKOptions
/// 3. 登录/登出（accid + token 由后端下发）
/// 4. 连接状态管理与监听
/// 5. 数据同步状态管理（防止同步完成前调用 SDK 导致原生层崩溃）
/// 6. 全局单例，供各页面调用
///
/// 安全机制：
/// - macOS/Windows 桌面端：NIM PC SDK 的 ConversationService 存在原生层缺陷
///   不注册 conversationService 的 onSyncFinished/onSyncFailed 监听
///   避免触发 C++ 异常导致 abort
///
/// 使用方式：
///   await IMService.instance.ensureInitialized(); // 延迟初始化
///   await IMService.instance.login(accid, token);
///   await IMService.instance.waitForDataSync();   // 等待数据同步完成
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

// 条件导入：平台检测
import 'platform_check_stub.dart'
    if (dart.library.io) 'platform_check_io.dart' as platformCheck;

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

  // ═══════════════════════════════════════════════════════
  // 平台检测
  // ═══════════════════════════════════════════════════════

  /// 检查当前平台是否为桌面端
  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return platformCheck.isDesktopPlatform();
  }

  // ═══════════════════════════════════════════════════════
  // 数据同步状态（关键：防止同步完成前调用 SDK 导致崩溃）
  // ═══════════════════════════════════════════════════════

  /// 数据同步是否完成（NIM PC SDK 要求同步完成后才能查询会话等数据）
  bool _isDataSyncCompleted = false;
  bool get isDataSyncCompleted => _isDataSyncCompleted;

  /// 数据同步完成的 Completer（供外部 await 等待）
  Completer<void>? _dataSyncCompleter;

  /// 等待数据同步完成（带超时保护）
  /// 返回 true 表示同步完成，false 表示超时
  Future<bool> waitForDataSync({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isDataSyncCompleted) return true;
    if (_dataSyncCompleter == null) return false;

    try {
      await _dataSyncCompleter!.future.timeout(timeout);
      return _isDataSyncCompleted;
    } on TimeoutException {
      _log('等待数据同步超时（${timeout.inSeconds}s），强制标记为完成');
      _isDataSyncCompleted = true;
      notifyListeners();
      return true;
    }
  }

  /// 连接状态变化流（供 UI 监听）
  final StreamController<IMConnectionStatus> _statusController =
      StreamController<IMConnectionStatus>.broadcast();
  Stream<IMConnectionStatus> get statusStream => _statusController.stream;

  /// 被踢出事件流
  final StreamController<String> _kickedController =
      StreamController<String>.broadcast();
  Stream<String> get kickedStream => _kickedController.stream;

  /// 数据同步完成事件流（供外部监听）
  final StreamController<void> _dataSyncFinishedController =
      StreamController<void>.broadcast();
  Stream<void> get dataSyncFinishedStream => _dataSyncFinishedController.stream;

  // Stream 订阅
  StreamSubscription<NIMLoginStatus>? _loginStatusSub;
  StreamSubscription<dynamic>? _loginFailedSub;
  StreamSubscription<NIMKickedOfflineDetail>? _kickedSub;
  StreamSubscription<NIMConnectStatus>? _connectStatusSub;
  StreamSubscription<NIMDataSyncDetail>? _dataSyncSub;
  StreamSubscription<void>? _convSyncFinishedSub;
  StreamSubscription<void>? _convSyncFailedSub;

  // ═══════════════════════════════════════════════════════
  // 延迟初始化
  // ═══════════════════════════════════════════════════════

  /// 确保 SDK 已初始化（延迟加载，首次调用时才初始化）
  Future<bool> ensureInitialized() async {
    if (_isInitialized) return true;
    if (_isInitializing) {
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
  Future<bool> login(String accid, String token) async {
    final initialized = await ensureInitialized();
    if (!initialized) {
      _log('SDK 未初始化，无法登录');
      return false;
    }

    // 重置数据同步状态
    _isDataSyncCompleted = false;
    _dataSyncCompleter = Completer<void>();

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
        _log('IM 登录成功，等待数据同步...');

        // ═══ 桌面端关键修复 ═══
        // 桌面端跳过了 conversationService 监听，loginService.onDataSync 可能不触发
        // 因此在桌面端登录成功后立即标记数据同步完成
        // 确保 _initIMServices 中 ChatMessageService.initialize() 能正常执行
        if (_isDesktopPlatform) {
          _log('桌面端：登录成功，立即标记数据同步完成');
          _markDataSyncCompleted();
        }

        return true;
      } else {
        _updateStatus(IMConnectionStatus.disconnected);
        _log('IM 登录失败: ${result.errorDetails}');
        _completeDataSync();
        return false;
      }
    } catch (e) {
      _updateStatus(IMConnectionStatus.disconnected);
      _log('IM 登录异常: $e');
      _completeDataSync();
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
      _isDataSyncCompleted = false;
      _dataSyncCompleter = null;
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
          _isDataSyncCompleted = false;
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
      _completeDataSync();
    });

    // 被踢下线监听
    _kickedSub = loginService.onKickedOffline.listen((detail) {
      _log('被踢下线');
      _currentAccid = null;
      _isDataSyncCompleted = false;
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

    // ═══ 数据同步监听（关键！防止同步完成前调用 SDK） ═══

    // 监听 loginService 的 onDataSync 事件
    _dataSyncSub = loginService.onDataSync.listen((detail) {
      _log('数据同步事件: type=${detail.type}, state=${detail.state}');
      if (detail.state == NIMDataSyncState.nimDataSyncStateCompleted) {
        _log('数据同步完成（来自 loginService.onDataSync）');
        _markDataSyncCompleted();
      }
    });

    // ═══ 关键修复：桌面端不注册 conversationService 监听 ═══
    // NIM PC SDK (macOS/Windows) 的 FLTConversationService 构造函数中
    // 注册 listener 时会抛出 std::runtime_error: misuse
    // 虽然构造函数有 try-catch，但后续对 conversationService 的任何调用
    // 都会触发未被 catch 的 C++ 异常导致 abort()
    // 因此在桌面端完全不接触 conversationService
    if (!_isDesktopPlatform) {
      try {
        final convService = NimCore.instance.conversationService;
        _convSyncFinishedSub = convService.onSyncFinished.listen((_) {
          _log('会话同步完成（来自 conversationService.onSyncFinished）');
          _markDataSyncCompleted();
        });
        _convSyncFailedSub = convService.onSyncFailed.listen((_) {
          _log('会话同步失败（来自 conversationService.onSyncFailed）');
          _markDataSyncCompleted();
        });
      } catch (e) {
        _log('注册会话同步监听失败（可能平台不支持）: $e');
      }
    } else {
      _log('桌面端平台，跳过 conversationService 监听注册（NIM PC SDK 不支持）');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════

  /// 标记数据同步完成
  void _markDataSyncCompleted() {
    if (!_isDataSyncCompleted) {
      _isDataSyncCompleted = true;
      _log('✅ 数据同步已完成，现在可以安全调用 SDK 查询接口');
      _completeDataSync();
      _dataSyncFinishedController.add(null);
      notifyListeners();
    }
  }

  /// 完成 Completer（安全调用，防止重复 complete）
  void _completeDataSync() {
    if (_dataSyncCompleter != null && !_dataSyncCompleter!.isCompleted) {
      _dataSyncCompleter!.complete();
    }
  }

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
    _dataSyncSub?.cancel();
    _convSyncFinishedSub?.cancel();
    _convSyncFailedSub?.cancel();
    _statusController.close();
    _kickedController.close();
    _dataSyncFinishedController.close();
    super.dispose();
  }
}
