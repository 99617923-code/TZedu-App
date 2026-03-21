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
/// - 移动端（iOS/Android）：正常调用 NIM SDK ConversationService
/// - 桌面端（macOS/Windows）：NIM PC SDK 的 ConversationService 存在原生层缺陷
///   （构造函数注册 listener 时抛出 misuse，后续所有调用均会触发 C++ 异常导致 abort）
///   因此在桌面端使用"本地会话管理"模式：
///   · 通过 SharedPreferences 持久化手动创建的会话
///   · 通过 MessageService 接收新消息时自动创建/更新本地会话
///   · 消息收发功能完全正常（MessageService 不受影响）
///
/// 使用方式：
///   final service = TZConversationService.instance;
///   service.conversationsStream.listen((list) { ... });

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// 序列化为 JSON（用于桌面端本地持久化）
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

  /// 从 JSON 反序列化（用于桌面端本地恢复）
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

class TZConversationService extends ChangeNotifier {
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

  // 桌面端新消息监听
  StreamSubscription<List<NIMMessage>>? _desktopMessageSub;

  // 本地持久化 Key
  static const String _localConversationsKey = 'tz_local_conversations';

  // ═══════════════════════════════════════════════════════
  // 平台安全检查
  // ═══════════════════════════════════════════════════════

  /// 检查当前平台是否为桌面端（macOS/Windows/Linux）
  /// NIM PC SDK 的 ConversationService 在桌面端存在原生层缺陷，必须跳过
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
    if (_isDesktopPlatform) {
      // ═══ 桌面端：本地会话管理模式 ═══
      _log('桌面端平台，使用本地会话管理模式');
      _isLoading = true;
      notifyListeners();

      // 从本地存储恢复会话列表
      await _loadLocalConversations();

      // 注册 MessageService 监听，自动更新本地会话
      _setupDesktopMessageListener();

      _isLoading = false;
      notifyListeners();
      return;
    }

    // ═══ 移动端：正常使用 NIM SDK ═══
    final imService = IMService.instance;

    if (!imService.isInitialized || !imService.isLoggedIn) {
      _log('IM 未就绪（未初始化或未登录），跳过会话服务初始化');
      return;
    }

    // 等待数据同步完成后再查询会话列表
    _log('等待 IM 数据同步完成...');
    final syncOk = await imService.waitForDataSync(timeout: const Duration(seconds: 15));
    if (!syncOk) {
      _log('数据同步等待失败，跳过会话加载');
      return;
    }
    _log('数据同步已完成，开始加载会话列表');

    _setupListeners();
    await loadConversations();
    await _refreshTotalUnread();
  }

  /// 注册会话变化监听（使用 Stream 方式）— 移动端专用
  void _setupListeners() {
    if (_listenerRegistered) return;
    if (_isDesktopPlatform) return;
    if (!_isIMReady) return;

    _listenerRegistered = true;

    final convService = NimCore.instance.conversationService;

    // 会话变化监听
    _convChangedSub = convService.onConversationChanged.listen((conversations) {
      _log('会话变化: ${conversations.length} 条');
      for (final conv in conversations) {
        _upsertConversation(conv);
      }
    });

    // 新会话创建监听
    _convCreatedSub = convService.onConversationCreated.listen((conversation) {
      _log('新会话创建: ${conversation.conversationId}');
      _upsertConversation(conversation);
    });

    // 会话删除监听
    _convDeletedSub =
        convService.onConversationDeleted.listen((conversationIds) {
      _log('会话删除: $conversationIds');
      _conversations.removeWhere(
        (c) => conversationIds.contains(c.conversationId),
      );
      _sortAndNotify();
    });

    // 总未读数变化监听
    _totalUnreadSub = convService.onTotalUnreadCountChanged.listen((count) {
      _log('总未读数变化: $count');
      _totalUnreadCount = count;
      _unreadController.add(count);
      notifyListeners();
    });
  }

  // ═══════════════════════════════════════════════════════
  // 桌面端：本地会话管理
  // ═══════════════════════════════════════════════════════

  /// 注册桌面端消息监听（通过 MessageService 自动创建/更新本地会话）
  void _setupDesktopMessageListener() {
    if (!_isDesktopPlatform) return;
    if (_desktopMessageSub != null) return; // 避免重复注册

    if (!_isIMLoggedIn) {
      _log('桌面端 IM 未登录，跳过消息监听注册');
      return;
    }

    try {
      final msgService = NimCore.instance.messageService;
      _desktopMessageSub = msgService.onReceiveMessages.listen((messages) {
        _log('桌面端收到新消息: ${messages.length} 条');
        for (final msg in messages) {
          _handleDesktopNewMessage(msg);
        }
      });
      _log('桌面端消息监听注册成功');
    } catch (e) {
      _log('桌面端消息监听注册失败: $e');
    }
  }

  /// 处理桌面端新消息（自动创建/更新本地会话）
  void _handleDesktopNewMessage(NIMMessage msg) {
    final conversationId = msg.conversationId ?? '';
    if (conversationId.isEmpty) return;

    final senderAccid = msg.senderId ?? '';
    final text = msg.text ?? '[消息]';
    final timestamp = msg.createTime != null
        ? DateTime.fromMillisecondsSinceEpoch(msg.createTime!)
        : DateTime.now();

    // 查找已有会话
    final existingIndex = _conversations.indexWhere(
      (c) => c.conversationId == conversationId,
    );

    if (existingIndex >= 0) {
      // 更新已有会话
      final existing = _conversations[existingIndex];
      _conversations[existingIndex] = existing.copyWith(
        lastMessage: _getMessageTypeText(msg),
        lastMessageTime: timestamp,
        unreadCount: existing.unreadCount + 1,
      );
    } else {
      // 创建新的本地会话
      final type = _guessConversationType(conversationId);
      final targetId = _extractTargetId(conversationId);

      _conversations.add(TZConversation(
        conversationId: conversationId,
        type: type,
        targetId: targetId,
        name: senderAccid, // 先用 accid，后续可通过 UserInfoService 更新
        lastMessage: _getMessageTypeText(msg),
        lastMessageTime: timestamp,
        unreadCount: 1,
      ));
    }

    _sortAndNotify();
    _saveLocalConversations();
    _recalculateUnread();
  }

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
    // conversationId 格式: {appId}|{type}|{targetId}
    // type: 1=P2P, 2=Team, 3=SuperTeam
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

  /// 手动添加/更新本地会话（桌面端发起新聊天时调用）
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
      // 更新已有会话的名称和头像（如果提供了新值）
      final existing = _conversations[existingIndex];
      _conversations[existingIndex] = existing.copyWith(
        name: name.isNotEmpty ? name : null,
        avatar: avatar.isNotEmpty ? avatar : null,
        lastMessage: lastMessage.isNotEmpty ? lastMessage : null,
        lastMessageTime: DateTime.now(),
      );
    } else {
      // 创建新会话
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
        _recalculateUnread();
        _log('从本地恢复 ${_conversations.length} 条会话');
      } else {
        _log('本地无缓存会话');
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

  /// 重新计算总未读数（桌面端本地计算）
  void _recalculateUnread() {
    _totalUnreadCount = _conversations.fold(0, (sum, c) => sum + c.unreadCount);
    _unreadController.add(_totalUnreadCount);
  }

  // ═══════════════════════════════════════════════════════
  // 会话列表操作
  // ═══════════════════════════════════════════════════════

  /// 加载会话列表（移动端从 SDK 加载）
  Future<void> loadConversations({bool isRetry = false}) async {
    if (_isDesktopPlatform) {
      // 桌面端从本地加载
      await _loadLocalConversations();
      return;
    }
    if (!_isIMReady) {
      _log('IM 未就绪，跳过加载会话列表');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final result = await NimCore.instance.conversationService
          .getConversationList(0, 200);

      if (result.isSuccess && result.data != null) {
        final nimConversations = result.data!.conversationList ?? [];
        _conversations = nimConversations
            .map((c) => _convertToTZConversation(c))
            .toList();
        _sortAndNotify();
        _log('加载会话列表成功: ${_conversations.length} 条');

        // 如果首次加载为空，延迟 3 秒重试一次（SDK 可能还没完全同步好会话数据）
        if (_conversations.isEmpty && !isRetry) {
          _log('会话列表为空，3秒后重试加载...');
          Future.delayed(const Duration(seconds: 3), () {
            loadConversations(isRetry: true);
          });
        }
      } else {
        _log('加载会话列表失败: ${result.errorDetails}');
        // 加载失败也延迟重试
        if (!isRetry) {
          Future.delayed(const Duration(seconds: 3), () {
            loadConversations(isRetry: true);
          });
        }
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
      // 桌面端本地置顶
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

    if (!_isIMReady) return false;

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
      // 桌面端本地删除
      _conversations.removeWhere((c) => c.conversationId == conversationId);
      _sortAndNotify();
      _recalculateUnread();
      await _saveLocalConversations();
      _log('本地删除会话: $conversationId');
      return true;
    }

    if (!_isIMReady) return false;

    try {
      final result = await NimCore.instance.conversationService
          .deleteConversation(conversationId, true);

      if (result.isSuccess) {
        _conversations.removeWhere((c) => c.conversationId == conversationId);
        _sortAndNotify();
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
    if (_isDesktopPlatform) {
      // 桌面端本地标记已读
      final index = _conversations.indexWhere((c) => c.conversationId == conversationId);
      if (index >= 0 && _conversations[index].unreadCount > 0) {
        _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
        _recalculateUnread();
        notifyListeners();
        await _saveLocalConversations();
      }
      return;
    }

    if (!_isIMReady) return;

    try {
      await NimCore.instance.conversationService
          .markConversationRead(conversationId);
      _log('标记已读: $conversationId');
    } catch (e) {
      _log('标记已读异常: $e');
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
  TZConversation _convertToTZConversation(NIMConversation conv) {
    // 提取最后一条消息的文本摘要
    String lastMsg = '';
    if (conv.lastMessage != null) {
      lastMsg = _getMessageSummary(conv.lastMessage!);
    }

    // 提取最后消息时间
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
  /// conversationId 格式: {appId}|{type}|{targetId}
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
  void _upsertConversation(NIMConversation nimConv) {
    final tzConv = _convertToTZConversation(nimConv);
    final index = _conversations.indexWhere(
      (c) => c.conversationId == tzConv.conversationId,
    );

    if (index >= 0) {
      _conversations[index] = tzConv;
    } else {
      _conversations.add(tzConv);
    }
    _sortAndNotify();
  }

  /// 排序并通知
  void _sortAndNotify() {
    _conversations.sort((a, b) {
      // 置顶优先
      if (a.isStickTop && !b.isStickTop) return -1;
      if (!a.isStickTop && b.isStickTop) return 1;
      // 按最后消息时间倒序
      final aTime = a.lastMessageTime ?? DateTime(2000);
      final bTime = b.lastMessageTime ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    _conversationsController.add(_conversations);
    notifyListeners();
  }

  /// 刷新总未读数（移动端从 SDK 获取）
  Future<void> _refreshTotalUnread() async {
    if (_isDesktopPlatform) {
      _recalculateUnread();
      return;
    }
    if (!_isIMReady) return;

    try {
      final result =
          await NimCore.instance.conversationService.getTotalUnreadCount();
      if (result.isSuccess && result.data != null) {
        _totalUnreadCount = result.data!;
        _unreadController.add(_totalUnreadCount);
        notifyListeners();
      }
    } catch (e) {
      _log('获取总未读数异常: $e');
    }
  }

  /// 重置服务状态（登出时调用）
  void reset() {
    _conversations = [];
    _totalUnreadCount = 0;
    _listenerRegistered = false;
    _convChangedSub?.cancel();
    _convCreatedSub?.cancel();
    _convDeletedSub?.cancel();
    _totalUnreadSub?.cancel();
    _desktopMessageSub?.cancel();
    _convChangedSub = null;
    _convCreatedSub = null;
    _convDeletedSub = null;
    _totalUnreadSub = null;
    _desktopMessageSub = null;
    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[TZConversationService] $message');
  }

  /// 释放资源
  @override
  void dispose() {
    _convChangedSub?.cancel();
    _convCreatedSub?.cancel();
    _convDeletedSub?.cancel();
    _totalUnreadSub?.cancel();
    _desktopMessageSub?.cancel();
    _conversationsController.close();
    _unreadController.close();
    super.dispose();
  }
}
