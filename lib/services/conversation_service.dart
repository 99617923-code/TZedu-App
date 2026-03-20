/// 途正英语 - 会话服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. 获取/监听会话列表
/// 2. 会话置顶/删除/免打扰
/// 3. 未读数管理
/// 4. 将云信 NIMConversation 转换为业务模型
///
/// 安全机制：
/// - macOS/Windows 桌面端：NIM PC SDK 的 ConversationService 存在原生层缺陷
///   （构造函数注册 listener 时抛出 misuse，后续所有调用均会触发 C++ 异常导致 abort）
///   因此在桌面端完全跳过 ConversationService 的原生调用，使用空列表
/// - 移动端（iOS/Android）：正常调用 NIM SDK
///
/// 使用方式：
///   final service = TZConversationService.instance;
///   service.conversationsStream.listen((list) { ... });

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'im_service.dart';

// 条件导入：用于平台检测
import 'platform_check_stub.dart'
    if (dart.library.io) 'platform_check_io.dart' as platformCheck;

/// 业务会话模型（从云信 NIMConversation 转换而来）
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

  /// 云信原始会话对象（保留以便后续操作）
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

  // ═══════════════════════════════════════════════════════
  // 平台安全检查
  // ═══════════════════════════════════════════════════════

  /// 检查当前平台是否为桌面端（macOS/Windows/Linux）
  /// NIM PC SDK 的 ConversationService 在桌面端存在原生层缺陷，必须跳过
  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return platformCheck.isDesktopPlatform();
  }

  /// 检查 IM SDK 是否已初始化、已登录且数据同步完成
  bool get _isIMReady =>
      !_isDesktopPlatform &&
      IMService.instance.isInitialized &&
      IMService.instance.isLoggedIn &&
      IMService.instance.isDataSyncCompleted;

  // ═══════════════════════════════════════════════════════
  // 初始化与监听
  // ═══════════════════════════════════════════════════════

  /// 初始化会话服务
  Future<void> initialize() async {
    // 桌面端：完全跳过 ConversationService 的原生调用
    if (_isDesktopPlatform) {
      _log('桌面端平台，跳过 ConversationService 原生调用（NIM PC SDK 不支持）');
      _isLoading = false;
      notifyListeners();
      return;
    }

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

  /// 注册会话变化监听（使用 Stream 方式）
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
  // 会话列表操作
  // ═══════════════════════════════════════════════════════

  /// 加载会话列表
  Future<void> loadConversations() async {
    if (_isDesktopPlatform) {
      _log('桌面端平台，跳过 getConversationList 调用');
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
      } else {
        _log('加载会话列表失败: ${result.errorDetails}');
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
    if (_isDesktopPlatform || !_isIMReady) return false;

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
    if (_isDesktopPlatform || !_isIMReady) return false;

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
    if (_isDesktopPlatform || !_isIMReady) return;

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

  /// 将云信会话转换为业务模型
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

  /// 获取消息摘要文本
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

  /// 更新或插入会话
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

  /// 刷新总未读数
  Future<void> _refreshTotalUnread() async {
    if (_isDesktopPlatform || !_isIMReady) return;

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
    _convChangedSub = null;
    _convCreatedSub = null;
    _convDeletedSub = null;
    _totalUnreadSub = null;
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
    _conversationsController.close();
    _unreadController.close();
    super.dispose();
  }
}
