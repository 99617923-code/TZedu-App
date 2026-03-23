/// 途正英语 - 会话服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. 获取/监听会话列表
/// 2. 会话置顶/删除/免打扰
/// 3. 未读数管理
/// 4. 将云信 NIMConversation 转换为业务模型
///
/// 双模式架构：
/// - 移动端（iOS/Android）：正常调用 NIM SDK ConversationService + 本地缓存
/// - 桌面端（macOS/Windows）：NIM PC SDK 的 ConversationService 存在原生层缺陷
///   因此在桌面端使用"本地会话管理"模式
///
/// 2026-03-23 修复：
/// - 修复移动端未读红点不显示的问题
/// - 移动端增加 onReceiveMessages 监听，收到新消息时手动累加未读数
/// - _upsertConversation 增加智能合并逻辑：SDK 返回 unreadCount=0 时保留本地未读数
/// - _refreshTotalUnread 增加回退机制：SDK 获取失败时从本地会话列表重新计算
/// - 统一所有端的未读数计算逻辑，确保一致性

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'im_service.dart';

// 条件导入：用于平台检测
import 'platform_check_stub.dart'
    if (dart.library.io) 'platform_check_io.dart' as platformCheck;

/// 业务会话模型（从云信 NIMConversation 转换而来，或桌面端本地创建）
class TZConversation {
  final String conversationId;
  final NIMConversationType type; // p2p / team / superTeam
  final String targetId; // 对方 accid 或群 teamId
  final String name;
  final String avatar;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isStickTop;
  final bool isMuted;

  /// 云信原始会话对象（保留以便后续操作，桌面端本地会话为 null）
  final NIMConversation? raw;

  TZConversation({
    required this.conversationId,
    required this.type,
    required this.targetId,
    this.name = '',
    this.avatar = '',
    this.lastMessage = '',
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isStickTop = false,
    this.isMuted = false,
    this.raw,
  });

  /// 序列化为 JSON（用于本地持久化）
  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'type': type.index,
    'targetId': targetId,
    'name': name,
    'avatar': avatar,
    'lastMessage': lastMessage,
    'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
    'unreadCount': unreadCount,
    'isStickTop': isStickTop,
    'isMuted': isMuted,
  };

  /// 从 JSON 反序列化（用于本地恢复）
  factory TZConversation.fromJson(Map<String, dynamic> json) {
    return TZConversation(
      conversationId: json['conversationId'] ?? '',
      type: NIMConversationType.values[json['type'] ?? 0],
      targetId: json['targetId'] ?? '',
      name: json['name'] ?? '',
      avatar: json['avatar'] ?? '',
      lastMessage: json['lastMessage'] ?? '',
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastMessageTime'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      isStickTop: json['isStickTop'] ?? false,
      isMuted: json['isMuted'] ?? false,
    );
  }

  /// 创建更新后的副本
  TZConversation copyWith({
    String? name,
    String? avatar,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isStickTop,
    bool? isMuted,
  }) {
    return TZConversation(
      conversationId: conversationId,
      type: type,
      targetId: targetId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isStickTop: isStickTop ?? this.isStickTop,
      isMuted: isMuted ?? this.isMuted,
      raw: raw,
    );
  }
}

class TZConversationService extends ChangeNotifier with WidgetsBindingObserver {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final TZConversationService _instance = TZConversationService._internal();
  static TZConversationService get instance => _instance;
  TZConversationService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  List<TZConversation> _conversations = [];
  List<TZConversation> get conversations => List.unmodifiable(_conversations);

  int _totalUnreadCount = 0;
  int get totalUnreadCount => _totalUnreadCount;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 是否已完成首次初始化
  bool _initialized = false;

  /// 会话列表变化流
  final StreamController<List<TZConversation>> _conversationsController =
      StreamController<List<TZConversation>>.broadcast();
  Stream<List<TZConversation>> get conversationsStream =>
      _conversationsController.stream;

  /// 总未读数变化流
  final StreamController<int> _unreadController =
      StreamController<int>.broadcast();
  Stream<int> get unreadStream => _unreadController.stream;

  bool _listenerRegistered = false;
  StreamSubscription<List<NIMConversation>>? _convChangedSub;
  StreamSubscription<NIMConversation>? _convCreatedSub;
  StreamSubscription<List<String>>? _convDeletedSub;
  StreamSubscription<int>? _totalUnreadSub;

  // 会话同步完成监听
  StreamSubscription<void>? _convSyncFinishedSub;
  StreamSubscription<void>? _convSyncFailedSub;
  bool _convSyncCompleted = false;

  // 新消息监听（移动端 + 桌面端都使用）
  StreamSubscription<List<NIMMessage>>? _messageReceivedSub;

  // IM 状态监听
  StreamSubscription<IMConnectionStatus>? _imStatusSub;

  // 本地持久化 Key
  static const String _localConversationsKey = 'tz_local_conversations';
  static const String _localUnreadCountKey = 'tz_local_unread_count';

  // 防抖：避免频繁刷新
  Timer? _refreshDebounceTimer;
  bool _isRefreshing = false;

  // 当前正在查看的会话 ID（用于判断是否需要增加未读数）
  String? _activeConversationId;

  // ═══════════════════════════════════════════════════════
  // 平台安全检查
  // ═══════════════════════════════════════════════════════

  /// 检查当前平台是否为桌面端（macOS/Windows/Linux）
  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return platformCheck.isDesktopPlatform();
  }

  /// 检查 IM SDK 是否已初始化、已登录且数据同步完成（移动端专用）
  bool get _isIMReady =>
      !_isDesktopPlatform &&
      IMService.instance.isInitialized &&
      IMService.instance.isLoggedIn &&
      IMService.instance.isDataSyncCompleted;

  /// 检查 IM SDK 是否已登录（桌面端也可用，不依赖 ConversationService）
  bool get _isIMLoggedIn =>
      IMService.instance.isInitialized &&
      IMService.instance.isLoggedIn;

  // ═══════════════════════════════════════════════════════
  // 初始化与监听
  // ═══════════════════════════════════════════════════════

  /// 初始化会话服务
  Future<void> initialize() async {
    _log('初始化会话服务... (桌面端: $_isDesktopPlatform, 已初始化: $_initialized)');

    // 注册 App 生命周期监听
    WidgetsBinding.instance.addObserver(this);

    if (_isDesktopPlatform) {
      // ═══ 桌面端：本地会话管理模式 ═══
      _log('桌面端平台，使用本地会话管理模式');
      _isLoading = true;
      notifyListeners();

      await _loadLocalConversations();
      _setupMessageListener();

      _isLoading = false;
      _initialized = true;
      notifyListeners();
      return;
    }

    // ═══ 移动端：NIM SDK + 本地缓存 + 消息监听 三重保障 ═══

    // 第一步：立即从本地缓存恢复会话列表（秒级显示，不等待网络）
    if (!_initialized) {
      _isLoading = true;
      notifyListeners();
      await _loadLocalConversations();
      _isLoading = false;
      notifyListeners();
      _log('从本地缓存恢复了 ${_conversations.length} 条会话，未读数: $_totalUnreadCount');
    }

    final imService = IMService.instance;

    if (!imService.isInitialized || !imService.isLoggedIn) {
      _log('IM 未就绪（未初始化或未登录），保持本地缓存数据');
      _initialized = true;
      return;
    }

    // 第二步：立即注册 SDK 监听器（必须在数据同步之前，避免遗漏事件）
    _setupListeners();

    // 第三步：注册新消息监听（关键！这是未读数的可靠来源）
    _setupMessageListener();

    // 第四步：等待数据同步完成
    _log('等待 IM 数据同步完成...');
    final syncOk = await imService.waitForDataSync(timeout: const Duration(seconds: 15));
    if (syncOk) {
      _log('数据同步已完成');
    } else {
      _log('数据同步等待超时，仍尝试加载会话列表...');
    }

    // 第五步：等待 ConversationService 同步完成
    if (!_convSyncCompleted) {
      _log('等待会话服务同步完成...');
      try {
        await NimCore.instance.conversationService.onSyncFinished.first
            .timeout(const Duration(seconds: 10));
        _convSyncCompleted = true;
        _log('会话服务同步完成');
      } catch (e) {
        _log('等待会话服务同步超时，仍尝试加载...');
      }
    }

    // 第六步：给 SDK 内部处理时间，然后加载会话列表
    await Future.delayed(const Duration(seconds: 2));
    _log('开始从 SDK 加载会话列表...');

    // 第七步：从 SDK 加载最新会话列表（带重试机制）
    await _loadConversationsWithRetry();
    await _refreshTotalUnread();

    // 第八步：监听 IM 连接状态变化（重连后自动刷新）
    _setupIMStatusListener();

    _initialized = true;
    _log('会话服务初始化完成，共 ${_conversations.length} 条会话，未读数: $_totalUnreadCount');
  }

  /// 设置当前正在查看的会话（进入聊天页面时调用）
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
    _log('当前活跃会话: $conversationId');
  }

  /// 延迟重试加载（数据同步超时时使用）
  void _scheduleRetryLoad() {
    Future.delayed(const Duration(seconds: 5), () async {
      if (_isIMLoggedIn) {
        _log('延迟重试：IM 已登录，重新加载');
        _setupListeners();
        _setupMessageListener();
        await loadConversations();
        await _refreshTotalUnread();
        _setupIMStatusListener();
      } else {
        _log('延迟重试：IM 仍未就绪，再次延迟');
        _scheduleRetryLoad();
      }
    });
  }

  /// 注册会话变化监听（使用 Stream 方式）— 移动端专用
  void _setupListeners() {
    if (_listenerRegistered) return;
    if (_isDesktopPlatform) return;
    if (!IMService.instance.isInitialized || !IMService.instance.isLoggedIn) {
      _log('IM 未初始化或未登录，延迟注册会话监听器');
      return;
    }

    _listenerRegistered = true;
    _log('注册会话变化监听器...');

    final convService = NimCore.instance.conversationService;

    // 会话变化监听（新消息、置顶等都会触发）
    _convChangedSub = convService.onConversationChanged.listen((conversations) {
      _log('会话变化回调: ${conversations.length} 条');
      for (final conv in conversations) {
        _upsertConversation(conv);
      }
      _saveLocalConversations();
    });

    // 新会话创建监听
    _convCreatedSub = convService.onConversationCreated.listen((conversation) {
      _log('新会话创建回调: ${conversation.conversationId}');
      _upsertConversation(conversation);
      _saveLocalConversations();
    });

    // 会话删除监听
    _convDeletedSub =
        convService.onConversationDeleted.listen((conversationIds) {
      _log('会话删除回调: $conversationIds');
      _conversations.removeWhere(
        (c) => conversationIds.contains(c.conversationId),
      );
      _sortAndNotify();
      _saveLocalConversations();
    });

    // 总未读数变化监听（关键：这是未读红点的数据来源之一）
    _totalUnreadSub = convService.onTotalUnreadCountChanged.listen((count) {
      _log('SDK 总未读数变化回调: $count (之前: $_totalUnreadCount)');
      if (count > 0) {
        // SDK 返回了有效的未读数，直接使用
        _totalUnreadCount = count;
        _unreadController.add(count);
        _saveUnreadCount(count);
        notifyListeners();
      } else {
        // SDK 返回 0，但本地可能有未读数，以本地计算为准
        final localCount = _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
        if (localCount > 0) {
          _log('SDK 返回未读数 0，但本地计算为 $localCount，使用本地值');
          _totalUnreadCount = localCount;
          _unreadController.add(localCount);
          _saveUnreadCount(localCount);
          notifyListeners();
        } else {
          _totalUnreadCount = 0;
          _unreadController.add(0);
          _saveUnreadCount(0);
          notifyListeners();
        }
      }
    });

    // 会话服务同步完成监听
    _convSyncFinishedSub = convService.onSyncFinished.listen((_) {
      _log('会话服务同步完成回调，标记同步完成');
      _convSyncCompleted = true;
      if (!_sdkLoadSuccess) {
        _log('同步完成，SDK加载尚未成功，自动重新加载会话列表...');
        Future.delayed(const Duration(seconds: 1), () async {
          await loadConversations();
          await _refreshTotalUnread();
        });
      }
    });

    // 会话服务同步失败监听
    _convSyncFailedSub = convService.onSyncFailed.listen((_) {
      _log('会话服务同步失败回调');
    });

    _log('会话变化监听器注册成功');
  }

  /// 注册新消息监听（所有端通用 — 关键修复！）
  /// 这是未读数的最可靠来源：每收到一条新消息，未读数 +1
  void _setupMessageListener() {
    if (_messageReceivedSub != null) return; // 避免重复注册

    if (!_isIMLoggedIn) {
      _log('IM 未登录，跳过消息监听注册');
      return;
    }

    try {
      final msgService = NimCore.instance.messageService;
      _messageReceivedSub = msgService.onReceiveMessages.listen((messages) {
        _log('收到新消息: ${messages.length} 条');
        for (final msg in messages) {
          _handleNewMessage(msg);
        }
      });
      _log('新消息监听注册成功（所有端通用）');
    } catch (e) {
      _log('新消息监听注册失败: $e');
    }
  }

  /// 处理新消息（自动创建/更新会话 + 累加未读数）
  /// 所有端通用：桌面端和移动端都通过此方法维护未读数
  void _handleNewMessage(NIMMessage msg) {
    final conversationId = msg.conversationId ?? '';
    if (conversationId.isEmpty) return;

    // 如果是自己发送的消息，不增加未读数
    final myAccid = IMService.instance.currentAccid;
    if (msg.senderId == myAccid) {
      _log('自己发送的消息，不增加未读数');
      // 但仍然更新会话的最后一条消息
      final existingIndex = _conversations.indexWhere(
        (c) => c.conversationId == conversationId,
      );
      if (existingIndex >= 0) {
        final existing = _conversations[existingIndex];
        final timestamp = msg.createTime != null
            ? DateTime.fromMillisecondsSinceEpoch(msg.createTime!)
            : DateTime.now();
        _conversations[existingIndex] = existing.copyWith(
          lastMessage: _getMessageTypeText(msg),
          lastMessageTime: timestamp,
        );
        _sortAndNotify();
        _saveLocalConversations();
      }
      return;
    }

    // 如果当前正在查看这个会话，不增加未读数
    if (_activeConversationId == conversationId) {
      _log('当前正在查看该会话，不增加未读数: $conversationId');
      final existingIndex = _conversations.indexWhere(
        (c) => c.conversationId == conversationId,
      );
      if (existingIndex >= 0) {
        final existing = _conversations[existingIndex];
        final timestamp = msg.createTime != null
            ? DateTime.fromMillisecondsSinceEpoch(msg.createTime!)
            : DateTime.now();
        _conversations[existingIndex] = existing.copyWith(
          lastMessage: _getMessageTypeText(msg),
          lastMessageTime: timestamp,
        );
        _sortAndNotify();
        _saveLocalConversations();
      }
      return;
    }

    final senderAccid = msg.senderId ?? '';
    final timestamp = msg.createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(msg.createTime!)
        : DateTime.now();

    final existingIndex = _conversations.indexWhere(
      (c) => c.conversationId == conversationId,
    );

    if (existingIndex >= 0) {
      final existing = _conversations[existingIndex];
      _conversations[existingIndex] = existing.copyWith(
        lastMessage: _getMessageTypeText(msg),
        lastMessageTime: timestamp,
        unreadCount: existing.unreadCount + 1,
      );
    } else {
      final type = _guessConversationType(conversationId);
      final targetId = _extractTargetId(conversationId);

      _conversations.add(TZConversation(
        conversationId: conversationId,
        type: type,
        targetId: targetId,
        name: senderAccid,
        lastMessage: _getMessageTypeText(msg),
        lastMessageTime: timestamp,
        unreadCount: 1,
      ));
    }

    _sortAndNotify();
    _saveLocalConversations();
    _recalculateUnread();
  }

  /// 监听 IM 连接状态变化（重连后自动刷新）
  void _setupIMStatusListener() {
    if (_imStatusSub != null) return;

    _imStatusSub = IMService.instance.statusStream.listen((status) {
      _log('IM 连接状态变化: $status');
      if (status == IMConnectionStatus.loggedIn ||
          status == IMConnectionStatus.connected) {
        _debouncedRefresh();
      }
    });
    _log('IM 状态监听器注册成功');
  }

  /// 防抖刷新（重连后 2 秒内只触发一次）
  void _debouncedRefresh() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(seconds: 2), () async {
      if (_isRefreshing) return;
      _isRefreshing = true;
      try {
        _log('重连后自动刷新会话列表和未读数...');
        _setupListeners();
        _setupMessageListener();
        await loadConversations();
        await _refreshTotalUnread();
        _log('重连后刷新完成');
      } catch (e) {
        _log('重连后刷新异常: $e');
      } finally {
        _isRefreshing = false;
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  // App 生命周期管理
  // ═══════════════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _log('App 从后台恢复，刷新会话列表和未读数');
      _debouncedRefresh();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 消息类型文本
  // ═══════════════════════════════════════════════════════

  /// 从消息中获取类型文本
  String _getMessageTypeText(NIMMessage msg) {
    switch (msg.messageType) {
      case NIMMessageType.text:
        return msg.text ?? '';
      case NIMMessageType.image:
        return '[图片]';
      case NIMMessageType.audio:
        return '[语音]';
      case NIMMessageType.video:
        return '[视频]';
      case NIMMessageType.file:
        return '[文件]';
      case NIMMessageType.location:
        return '[位置]';
      case NIMMessageType.notification:
        return '[通知]';
      case NIMMessageType.tip:
        return '[提示]';
      case NIMMessageType.custom:
        return '[自定义消息]';
      default:
        return '[消息]';
    }
  }

  /// 从 conversationId 猜测会话类型
  NIMConversationType _guessConversationType(String conversationId) {
    final parts = conversationId.split('|');
    if (parts.length >= 2) {
      switch (parts[1]) {
        case '1':
          return NIMConversationType.p2p;
        case '2':
          return NIMConversationType.team;
        case '3':
          return NIMConversationType.superTeam;
      }
    }
    return NIMConversationType.p2p;
  }

  /// 手动添加/更新本地会话（发起新聊天时调用）
  Future<void> addOrUpdateLocalConversation({
    required String conversationId,
    required NIMConversationType type,
    required String targetId,
    String name = '',
    String avatar = '',
    String lastMessage = '',
  }) async {
    final existingIndex = _conversations.indexWhere(
      (c) => c.conversationId == conversationId,
    );

    if (existingIndex >= 0) {
      final existing = _conversations[existingIndex];
      _conversations[existingIndex] = existing.copyWith(
        name: name.isNotEmpty ? name : null,
        avatar: avatar.isNotEmpty ? avatar : null,
        lastMessage: lastMessage.isNotEmpty ? lastMessage : null,
        lastMessageTime: DateTime.now(),
      );
    } else {
      _conversations.add(TZConversation(
        conversationId: conversationId,
        type: type,
        targetId: targetId,
        name: name,
        avatar: avatar,
        lastMessage: lastMessage,
        lastMessageTime: DateTime.now(),
      ));
    }

    _sortAndNotify();
    await _saveLocalConversations();
    _log('本地会话已添加/更新: $conversationId ($name)');
  }

  /// 从本地存储加载会话列表
  Future<void> _loadLocalConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final jsonStr = prefs.getString(_localConversationsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _conversations = jsonList
            .map((j) => TZConversation.fromJson(j as Map<String, dynamic>))
            .toList();
        _sortAndNotify();
        _log('从本地恢复 ${_conversations.length} 条会话');
      } else {
        _log('本地无缓存会话');
      }

      final savedUnread = prefs.getInt(_localUnreadCountKey);
      if (savedUnread != null) {
        _totalUnreadCount = savedUnread;
        _unreadController.add(_totalUnreadCount);
        notifyListeners();
        _log('从本地恢复未读数: $_totalUnreadCount');
      }
    } catch (e) {
      _log('加载本地会话异常: $e');
    }
  }

  /// 保存会话列表到本地存储
  Future<void> _saveLocalConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_conversations.map((c) => c.toJson()).toList());
      await prefs.setString(_localConversationsKey, jsonStr);
    } catch (e) {
      _log('保存本地会话异常: $e');
    }
  }

  /// 保存未读数到本地存储
  Future<void> _saveUnreadCount(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_localUnreadCountKey, count);
    } catch (e) {
      _log('保存未读数异常: $e');
    }
  }

  /// 重新计算总未读数（从本地会话列表计算，所有端通用）
  void _recalculateUnread() {
    _totalUnreadCount = _conversations.fold(0, (sum, c) => sum + c.unreadCount);
    _unreadController.add(_totalUnreadCount);
    _saveUnreadCount(_totalUnreadCount);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  // 会话列表操作
  // ═══════════════════════════════════════════════════════

  /// 带重试机制的加载会话列表（初始化时使用）
  bool _sdkLoadSuccess = false;
  Future<void> _loadConversationsWithRetry({int maxRetries = 5}) async {
    _sdkLoadSuccess = false;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      _log('加载会话列表尝试 $attempt/$maxRetries');
      await loadConversations(isRetry: attempt > 1);

      if (_sdkLoadSuccess) {
        _log('从SDK加载会话列表成功，尝试次数: $attempt');
        return;
      }

      if (attempt < maxRetries) {
        final delay = Duration(seconds: attempt * 2);
        _log('SDK加载失败，${delay.inSeconds}秒后重试...');
        await Future.delayed(delay);
      }
    }
    _log('加载会话列表失败，已达最大重试次数，使用本地缓存数据');
  }

  /// 加载会话列表（移动端从 SDK 加载）
  Future<void> loadConversations({bool isRetry = false}) async {
    if (_isDesktopPlatform) {
      await _loadLocalConversations();
      return;
    }
    if (!IMService.instance.isInitialized || !IMService.instance.isLoggedIn) {
      _log('IM 未就绪，跳过加载会话列表');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      List<NIMConversation> allConversations = [];
      int offset = 0;
      const int pageSize = 100;
      bool hasMore = true;

      while (hasMore) {
        _log('加载会话列表: offset=$offset, limit=$pageSize');
        final result = await NimCore.instance.conversationService
            .getConversationList(offset, pageSize);

        if (result.isSuccess && result.data != null) {
          final nimConversations = result.data!.conversationList ?? [];
          allConversations.addAll(nimConversations);
          offset = result.data!.offset;
          hasMore = !result.data!.finished && nimConversations.isNotEmpty;
          _log('本页加载 ${nimConversations.length} 条，总计 ${allConversations.length} 条，还有更多: $hasMore');
        } else {
          _log('加载会话列表失败: code=${result.code}, error=${result.errorDetails}');
          hasMore = false;
        }
      }

      if (allConversations.isNotEmpty) {
        // ═══ 关键修复：智能合并 SDK 数据和本地未读数 ═══
        final newConversations = allConversations
            .map((c) => _convertToTZConversationWithLocalUnread(c))
            .toList();
        _conversations = newConversations;
        _sortAndNotify();
        _sdkLoadSuccess = true;
        _log('从 SDK 加载会话列表成功: ${_conversations.length} 条');

        // 保存到本地缓存
        await _saveLocalConversations();
        // 重新计算未读数
        _recalculateUnread();
      } else if (offset == 0) {
        _sdkLoadSuccess = true;
        _log('会话列表为空（SDK 返回成功但无数据）');
      } else {
        _log('会话列表为空');
      }
    } catch (e) {
      _log('加载会话列表异常: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 置顶/取消置顶会话
  Future<bool> toggleStickTop(String conversationId) async {
    if (_isDesktopPlatform) {
      final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
      if (index >= 0) {
        _conversations[index] = _conversations[index].copyWith(
          isStickTop: !_conversations[index].isStickTop,
        );
        _sortAndNotify();
        await _saveLocalConversations();
        return true;
      }
      return false;
    }

    if (!_isIMLoggedIn) return false;

    try {
      final conv = _conversations.firstWhere(
        (c) => c.conversationId == conversationId,
        orElse: () => throw Exception('会话不存在'),
      );

      final result = await NimCore.instance.conversationService
          .stickTopConversation(conversationId, !conv.isStickTop);

      if (result.isSuccess) {
        _log('${conv.isStickTop ? "取消" : ""}置顶成功: $conversationId');
        return true;
      }
      return false;
    } catch (e) {
      _log('置顶操作异常: $e');
      return false;
    }
  }

  /// 删除会话
  Future<bool> deleteConversation(String conversationId) async {
    if (_isDesktopPlatform) {
      _conversations.removeWhere((c) => c.conversationId == conversationId);
      _sortAndNotify();
      _recalculateUnread();
      await _saveLocalConversations();
      _log('本地删除会话: $conversationId');
      return true;
    }

    if (!_isIMLoggedIn) return false;

    try {
      final result = await NimCore.instance.conversationService
          .deleteConversation(conversationId, true);

      if (result.isSuccess) {
        _conversations.removeWhere((c) => c.conversationId == conversationId);
        _sortAndNotify();
        _recalculateUnread();
        await _saveLocalConversations();
        _log('删除会话成功: $conversationId');
        return true;
      }
      return false;
    } catch (e) {
      _log('删除会话异常: $e');
      return false;
    }
  }

  /// 标记会话已读
  Future<void> markConversationRead(String conversationId) async {
    // 先立即更新本地状态（所有端通用）
    final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index >= 0 && _conversations[index].unreadCount > 0) {
      _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
      _recalculateUnread();
      _sortAndNotify();
      await _saveLocalConversations();
      _log('本地标记已读: $conversationId');
    }

    if (_isDesktopPlatform) return;
    if (!_isIMLoggedIn) return;

    try {
      final result = await NimCore.instance.conversationService
          .clearUnreadCountByIds([conversationId]);

      if (result.isSuccess) {
        _log('SDK 标记已读成功: $conversationId');
      } else {
        _log('SDK 标记已读失败: code=${result.code}, error=${result.errorDetails}');
        try {
          await NimCore.instance.conversationService
              .markConversationRead(conversationId);
          _log('SDK 标记已读(fallback): $conversationId');
        } catch (e2) {
          _log('SDK 标记已读(fallback)异常: $e2');
        }
      }
    } catch (e) {
      _log('SDK 标记已读异常: $e');
    }
  }

  /// 切换会话免打扰
  Future<bool> toggleMute(String conversationId) async {
    if (_isDesktopPlatform) {
      final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
      if (index >= 0) {
        final current = _conversations[index];
        _conversations[index] = current.copyWith(isMuted: !current.isMuted);
        _sortAndNotify();
        await _saveLocalConversations();
        return true;
      }
      return false;
    }

    if (!_isIMLoggedIn) return false;

    try {
      final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
      if (index < 0) return false;

      final conv = _conversations[index];
      final currentMuted = conv.isMuted;
      final targetId = conv.targetId;

      if (conv.type == NIMConversationType.p2p) {
        final result = await NimCore.instance.settingsService
            .setP2PMessageMuteMode(
              targetId,
              currentMuted
                  ? NIMP2PMessageMuteMode.p2pMessageMuteModeOff
                  : NIMP2PMessageMuteMode.p2pMessageMuteModeOn,
            );
        if (result.isSuccess) {
          _conversations[index] = conv.copyWith(isMuted: !currentMuted);
          _sortAndNotify();
          await _saveLocalConversations();
          _log('切换单聊免打扰成功: $conversationId -> ${!currentMuted}');
          return true;
        }
      } else {
        final result = await NimCore.instance.settingsService
            .setTeamMessageMuteMode(
              targetId,
              conv.type == NIMConversationType.superTeam
                  ? NIMTeamType.typeSuper
                  : NIMTeamType.typeNormal,
              currentMuted
                  ? NIMTeamMessageMuteMode.teamMessageMuteModeOff
                  : NIMTeamMessageMuteMode.teamMessageMuteModeOn,
            );
        if (result.isSuccess) {
          _conversations[index] = conv.copyWith(isMuted: !currentMuted);
          _sortAndNotify();
          await _saveLocalConversations();
          _log('切换群聊免打扰成功: $conversationId -> ${!currentMuted}');
          return true;
        }
      }
      return false;
    } catch (e) {
      _log('切换免打扰异常: $e');
      final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
      if (index >= 0) {
        final current = _conversations[index];
        _conversations[index] = current.copyWith(isMuted: !current.isMuted);
        _sortAndNotify();
        await _saveLocalConversations();
        _log('免打扰回退到本地标记');
        return true;
      }
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 搜索
  // ═══════════════════════════════════════════════════════

  /// 按名称搜索会话（本地过滤）
  List<TZConversation> searchByName(String keyword) {
    if (keyword.isEmpty) return _conversations;
    final lower = keyword.toLowerCase();
    return _conversations
        .where((c) => c.name.toLowerCase().contains(lower))
        .toList();
  }

  /// 按类型筛选会话
  List<TZConversation> filterByType(NIMConversationType? type) {
    if (type == null) return _conversations;
    return _conversations.where((c) => c.type == type).toList();
  }

  // ═══════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════

  /// 将云信会话转换为业务模型（移动端专用）
  /// 智能合并：如果 SDK 返回的 unreadCount 为 0，保留本地已有的未读数
  TZConversation _convertToTZConversationWithLocalUnread(NIMConversation conv) {
    String lastMsg = '';
    if (conv.lastMessage != null) {
      lastMsg = _getMessageSummary(conv.lastMessage!);
    }

    DateTime? lastMsgTime;
    if (conv.lastMessage?.messageRefer?.createTime != null) {
      lastMsgTime = DateTime.fromMillisecondsSinceEpoch(
        conv.lastMessage!.messageRefer!.createTime!,
      );
    }

    final sdkUnread = conv.unreadCount ?? 0;

    // 查找本地已有的未读数
    int localUnread = 0;
    final existingIndex = _conversations.indexWhere(
      (c) => c.conversationId == conv.conversationId,
    );
    if (existingIndex >= 0) {
      localUnread = _conversations[existingIndex].unreadCount;
    }

    // 智能合并：取 SDK 和本地的较大值
    final finalUnread = sdkUnread > localUnread ? sdkUnread : localUnread;
    if (sdkUnread != finalUnread) {
      _log('未读数智能合并: ${conv.conversationId} SDK=$sdkUnread 本地=$localUnread -> 使用=$finalUnread');
    }

    return TZConversation(
      conversationId: conv.conversationId,
      type: conv.type,
      targetId: _extractTargetId(conv.conversationId),
      name: conv.name ?? '',
      avatar: conv.avatar ?? '',
      lastMessage: lastMsg,
      lastMessageTime: lastMsgTime,
      unreadCount: finalUnread,
      isStickTop: conv.stickTop,
      isMuted: conv.mute,
      raw: conv,
    );
  }

  /// 将云信会话转换为业务模型（纯 SDK 数据，用于 onConversationChanged 回调）
  TZConversation _convertToTZConversation(NIMConversation conv) {
    String lastMsg = '';
    if (conv.lastMessage != null) {
      lastMsg = _getMessageSummary(conv.lastMessage!);
    }

    DateTime? lastMsgTime;
    if (conv.lastMessage?.messageRefer?.createTime != null) {
      lastMsgTime = DateTime.fromMillisecondsSinceEpoch(
        conv.lastMessage!.messageRefer!.createTime!,
      );
    }

    return TZConversation(
      conversationId: conv.conversationId,
      type: conv.type,
      targetId: _extractTargetId(conv.conversationId),
      name: conv.name ?? '',
      avatar: conv.avatar ?? '',
      lastMessage: lastMsg,
      lastMessageTime: lastMsgTime,
      unreadCount: conv.unreadCount ?? 0,
      isStickTop: conv.stickTop,
      isMuted: conv.mute,
      raw: conv,
    );
  }

  /// 从 conversationId 中提取 targetId
  String _extractTargetId(String conversationId) {
    final parts = conversationId.split('|');
    return parts.length >= 3 ? parts[2] : conversationId;
  }

  /// 获取消息摘要文本（移动端 NIMLastMessage）
  String _getMessageSummary(NIMLastMessage lastMessage) {
    switch (lastMessage.messageType) {
      case NIMMessageType.text:
        return lastMessage.text ?? '';
      case NIMMessageType.image:
        return '[图片]';
      case NIMMessageType.audio:
        return '[语音]';
      case NIMMessageType.video:
        return '[视频]';
      case NIMMessageType.file:
        return '[文件]';
      case NIMMessageType.location:
        return '[位置]';
      case NIMMessageType.notification:
        return '[通知]';
      case NIMMessageType.tip:
        return '[提示]';
      case NIMMessageType.custom:
        return '[自定义消息]';
      default:
        return '[消息]';
    }
  }

  /// 更新或插入会话（移动端 NIM SDK 回调）
  /// 智能合并：SDK 回调的 unreadCount 如果为 0，保留本地已有的未读数
  void _upsertConversation(NIMConversation nimConv) {
    final sdkConv = _convertToTZConversation(nimConv);
    final index = _conversations.indexWhere(
      (c) => c.conversationId == sdkConv.conversationId,
    );

    if (index >= 0) {
      final existing = _conversations[index];
      // ═══ 关键修复：智能合并未读数 ═══
      // SDK 回调的 unreadCount 可能为 0（移动端 SDK bug），此时保留本地的未读数
      int finalUnread;
      if (sdkConv.unreadCount > 0) {
        // SDK 返回了有效的未读数，使用 SDK 的值
        finalUnread = sdkConv.unreadCount;
      } else if (existing.unreadCount > 0) {
        // SDK 返回 0 但本地有未读数，保留本地值
        finalUnread = existing.unreadCount;
        _log('_upsertConversation: SDK unreadCount=0，保留本地值=$finalUnread (${nimConv.conversationId})');
      } else {
        finalUnread = 0;
      }

      _conversations[index] = TZConversation(
        conversationId: sdkConv.conversationId,
        type: sdkConv.type,
        targetId: sdkConv.targetId,
        name: sdkConv.name.isNotEmpty ? sdkConv.name : existing.name,
        avatar: sdkConv.avatar.isNotEmpty ? sdkConv.avatar : existing.avatar,
        lastMessage: sdkConv.lastMessage.isNotEmpty ? sdkConv.lastMessage : existing.lastMessage,
        lastMessageTime: sdkConv.lastMessageTime ?? existing.lastMessageTime,
        unreadCount: finalUnread,
        isStickTop: sdkConv.isStickTop,
        isMuted: sdkConv.isMuted,
        raw: sdkConv.raw,
      );
    } else {
      _conversations.add(sdkConv);
    }
    _sortAndNotify();
    // 同步更新总未读数
    _recalculateUnread();
  }

  /// 排序并通知
  void _sortAndNotify() {
    _conversations.sort((a, b) {
      if (a.isStickTop && !b.isStickTop) return -1;
      if (!a.isStickTop && b.isStickTop) return 1;
      final aTime = a.lastMessageTime ?? DateTime(2000);
      final bTime = b.lastMessageTime ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    _conversationsController.add(_conversations);
    notifyListeners();
  }

  /// 刷新总未读数（优先从 SDK 获取，失败则从本地计算）
  Future<void> _refreshTotalUnread() async {
    if (_isDesktopPlatform) {
      _recalculateUnread();
      return;
    }
    if (!_isIMLoggedIn) return;

    try {
      final result =
          await NimCore.instance.conversationService.getTotalUnreadCount();
      if (result.isSuccess && result.data != null && result.data! > 0) {
        _totalUnreadCount = result.data!;
        _unreadController.add(_totalUnreadCount);
        await _saveUnreadCount(_totalUnreadCount);
        notifyListeners();
        _log('从 SDK 获取总未读数: $_totalUnreadCount');
      } else {
        // SDK 返回 0 或失败，从本地会话列表重新计算
        _log('SDK 总未读数为 ${result.data ?? "null"}，从本地计算');
        _recalculateUnread();
      }
    } catch (e) {
      _log('获取总未读数异常: $e，从本地计算');
      _recalculateUnread();
    }
  }

  /// 重置服务状态（登出时调用）
  void reset() {
    _conversations = [];
    _totalUnreadCount = 0;
    _listenerRegistered = false;
    _initialized = false;
    _convSyncCompleted = false;
    _sdkLoadSuccess = false;
    _activeConversationId = null;
    _convChangedSub?.cancel();
    _convCreatedSub?.cancel();
    _convDeletedSub?.cancel();
    _totalUnreadSub?.cancel();
    _convSyncFinishedSub?.cancel();
    _convSyncFailedSub?.cancel();
    _messageReceivedSub?.cancel();
    _imStatusSub?.cancel();
    _refreshDebounceTimer?.cancel();
    _convChangedSub = null;
    _convCreatedSub = null;
    _convDeletedSub = null;
    _totalUnreadSub = null;
    _convSyncFinishedSub = null;
    _convSyncFailedSub = null;
    _messageReceivedSub = null;
    _imStatusSub = null;
    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[TZConversationService] $message');
  }

  /// 释放资源
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _convChangedSub?.cancel();
    _convCreatedSub?.cancel();
    _convDeletedSub?.cancel();
    _totalUnreadSub?.cancel();
    _convSyncFinishedSub?.cancel();
    _convSyncFailedSub?.cancel();
    _messageReceivedSub?.cancel();
    _imStatusSub?.cancel();
    _refreshDebounceTimer?.cancel();
    _conversationsController.close();
    _unreadController.close();
    super.dispose();
  }
}
