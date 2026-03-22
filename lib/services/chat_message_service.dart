/// 途正英语 - 消息服务层（网易云信 nim_core_v2）
/// 火鹰科技出品
///
/// 职责：
/// 1. 发送消息（文本/图片/语音/视频/文件/自定义）
/// 2. 接收消息（实时监听）
/// 3. 查询历史消息
/// 4. 消息撤回、已读回执
/// 5. 消息删除、转发
/// 6. 本地消息搜索
/// 7. 将云信 NIMMessage 转换为业务模型
///
/// 安全机制：
/// - 所有 NIM SDK 调用前都检查 IM 初始化和登录状态
/// - 防止 SDK 未初始化时原生层 abort() 导致闪退
///
/// 使用方式：
///   final service = ChatMessageService.instance;
///   service.sendTextMessage(conversationId, '你好');
///   service.messageStream.listen((msg) { ... });

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../config/im_config.dart';
import 'im_service.dart';
import 'conversation_service.dart';

/// 业务消息模型（从云信 NIMMessage 转换而来）
class TZMessage {
  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final TZMessageType type;
  final String text;
  final String? imageUrl;
  final String? audioUrl;
  final int? audioDuration; // 语音时长（秒）
  final String? videoUrl;
  final String? videoCoverUrl; // 视频封面
  final int? videoDuration; // 视频时长（秒）
  final String? fileUrl;
  final String? fileName;
  final int? fileSize; // 文件大小（字节）
  final double? latitude;
  final double? longitude;
  final String? locationTitle;
  final Map<String, dynamic>? customData;
  final DateTime timestamp;
  final TZMessageStatus status;
  final bool isRevoked;

  /// 云信原始消息对象
  final NIMMessage? raw;

  TZMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    this.senderName = '',
    this.senderAvatar = '',
    required this.type,
    this.text = '',
    this.imageUrl,
    this.audioUrl,
    this.audioDuration,
    this.videoUrl,
    this.videoCoverUrl,
    this.videoDuration,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.latitude,
    this.longitude,
    this.locationTitle,
    this.customData,
    required this.timestamp,
    this.status = TZMessageStatus.success,
    this.isRevoked = false,
    this.raw,
  });

  /// 是否是自己发的消息
  bool get isMine => senderId == IMService.instance.currentAccid;
}

enum TZMessageType {
  text,
  image,
  audio,
  video,
  file,
  location,
  custom,
  notification,
  tip,
  unknown,
}

enum TZMessageStatus {
  sending,
  success,
  failed,
}

class ChatMessageService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final ChatMessageService _instance = ChatMessageService._internal();
  static ChatMessageService get instance => _instance;
  ChatMessageService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  /// 新消息流（所有会话的新消息）
  final StreamController<List<TZMessage>> _messageController =
      StreamController<List<TZMessage>>.broadcast();
  Stream<List<TZMessage>> get messageStream => _messageController.stream;

  /// 消息撤回流
  final StreamController<List<String>> _revokeController =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get revokeStream => _revokeController.stream;

  /// 消息发送进度流
  final StreamController<({String messageId, int progress})>
      _progressController =
      StreamController<({String messageId, int progress})>.broadcast();
  Stream<({String messageId, int progress})> get progressStream =>
      _progressController.stream;

  /// 消息状态变化流（发送成功/失败）
  final StreamController<({String messageId, TZMessageStatus status})>
      _statusController =
      StreamController<({String messageId, TZMessageStatus status})>.broadcast();
  Stream<({String messageId, TZMessageStatus status})> get statusStream =>
      _statusController.stream;

  bool _listenerRegistered = false;
  StreamSubscription<List<NIMMessage>>? _receiveMessageSub;
  StreamSubscription<List<NIMMessageRevokeNotification>>? _revokeSub;
  StreamSubscription<List<NIMP2PMessageReadReceipt>>? _p2pReceiptSub;
  StreamSubscription<List<NIMTeamMessageReadReceipt>>? _teamReceiptSub;

  // ═══════════════════════════════════════════════════════
  // 安全检查
  // ═══════════════════════════════════════════════════════

  /// 检查 IM SDK 是否已初始化、已登录且数据同步完成
  bool get _isIMReady =>
      IMService.instance.isInitialized &&
      IMService.instance.isLoggedIn &&
      IMService.instance.isDataSyncCompleted;

  /// 宽松检查：只要 SDK 已初始化且已登录即可（不要求数据同步完成）
  /// 桌面端数据同步状态可能在 initialize 调用时还未就绪
  bool get _isIMConnected =>
      IMService.instance.isInitialized &&
      IMService.instance.isLoggedIn;

  // ═══════════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════════

  /// 初始化消息服务（在 IM 登录成功后调用）
  void initialize() {
    _log('initialize 调用 - isInitialized: ${IMService.instance.isInitialized}, '
        'isLoggedIn: ${IMService.instance.isLoggedIn}, '
        'isDataSyncCompleted: ${IMService.instance.isDataSyncCompleted}, '
        'currentAccid: ${IMService.instance.currentAccid}');

    if (!_isIMConnected) {
      _log('IM 未连接（未初始化或未登录），跳过消息服务初始化');
      return;
    }
    _setupListeners();
  }

  /// 注册消息监听（使用 Stream 方式）
  void _setupListeners() {
    if (_listenerRegistered) return;
    if (!_isIMConnected) return;

    _listenerRegistered = true;
    _log('消息监听注册成功！accid: ${IMService.instance.currentAccid}');

    final msgService = NimCore.instance.messageService;

    // 接收新消息
    _receiveMessageSub = msgService.onReceiveMessages.listen((messages) {
      _log('收到新消息: ${messages.length} 条');
      for (final m in messages) {
        _log('  → from: ${m.senderId}, convId: ${m.conversationId}, type: ${m.messageType}');
      }
      final tzMessages =
          messages.map((m) => _convertToTZMessage(m)).toList();
      _messageController.add(tzMessages);

      // ═══ 关键修复：收到新消息时自动更新会话列表 ═══
      for (final msg in messages) {
        _autoUpdateConversation(msg);
      }
    });

    // 消息撤回通知
    _revokeSub =
        msgService.onMessageRevokeNotifications.listen((notifications) {
      _log('消息撤回通知: ${notifications.length} 条');
      final ids = notifications
          .map((n) => n.messageRefer?.messageClientId ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      _revokeController.add(ids);
    });

    // P2P 已读回执
    _p2pReceiptSub =
        msgService.onReceiveP2PMessageReadReceipts.listen((receipts) {
      _log('P2P 已读回执: ${receipts.length} 条');
    });

    // 群已读回执
    _teamReceiptSub =
        msgService.onReceiveTeamMessageReadReceipts.listen((receipts) {
      _log('群已读回执: ${receipts.length} 条');
    });
  }

  // ═══════════════════════════════════════════════════════
  // 发送消息
  // ═══════════════════════════════════════════════════════

  /// 发送文本消息
  Future<TZMessage?> sendTextMessage(
    String conversationId,
    String text,
  ) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送文本消息');
      return null;
    }

    try {
      _log('发送文本消息到: $conversationId');

      final createResult = await MessageCreator.createTextMessage(text);

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建文本消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data != null) {
        _log('文本消息发送成功');
        final sentMsg = sendResult.data!.message;
        if (sentMsg != null) {
          return _convertToTZMessage(sentMsg);
        }
      } else {
        _log('文本消息发送失败: ${sendResult.errorDetails}');
      }
      return null;
    } catch (e) {
      _log('发送文本消息异常: $e');
      return null;
    }
  }

  /// 发送图片消息
  Future<TZMessage?> sendImageMessage(
    String conversationId,
    String imagePath, {
    int width = 0,
    int height = 0,
  }) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送图片消息');
      return null;
    }

    try {
      _log('发送图片消息到: $conversationId');

      final createResult = await MessageCreator.createImageMessage(
        imagePath,
        null, // name
        null, // sceneName
        width,
        height,
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建图片消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('图片消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('图片消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送图片消息异常: $e');
      return null;
    }
  }

  /// 发送语音消息
  Future<TZMessage?> sendAudioMessage(
    String conversationId,
    String audioPath,
    int duration,
  ) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送语音消息');
      return null;
    }

    try {
      _log('发送语音消息到: $conversationId');

      final createResult = await MessageCreator.createAudioMessage(
        audioPath,
        null, // name
        null, // sceneName
        duration,
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建语音消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('语音消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('语音消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送语音消息异常: $e');
      return null;
    }
  }

  /// 发送视频消息
  Future<TZMessage?> sendVideoMessage(
    String conversationId,
    String videoPath, {
    int duration = 0,
    int width = 0,
    int height = 0,
  }) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送视频消息');
      return null;
    }

    try {
      _log('发送视频消息到: $conversationId');

      final createResult = await MessageCreator.createVideoMessage(
        videoPath,
        null, // name
        null, // sceneName
        duration,
        width,
        height,
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建视频消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('视频消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('视频消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送视频消息异常: $e');
      return null;
    }
  }

  /// 发送文件消息
  Future<TZMessage?> sendFileMessage(
    String conversationId,
    String filePath, {
    String? displayName,
  }) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送文件消息');
      return null;
    }

    try {
      _log('发送文件消息到: $conversationId');

      final createResult = await MessageCreator.createFileMessage(
        filePath,
        displayName, // name
        null, // sceneName
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建文件消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('文件消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('文件消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送文件消息异常: $e');
      return null;
    }
  }

  /// 发送位置消息
  Future<TZMessage?> sendLocationMessage(
    String conversationId, {
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送位置消息');
      return null;
    }

    try {
      _log('发送位置消息到: $conversationId');

      final createResult = await MessageCreator.createLocationMessage(
        latitude,
        longitude,
        address,
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建位置消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('位置消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('位置消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送位置消息异常: $e');
      return null;
    }
  }

  /// 发送自定义消息（用于业务扩展，如作业提交、AI评分等）
  Future<TZMessage?> sendCustomMessage(
    String conversationId,
    Map<String, dynamic> data,
  ) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法发送自定义消息');
      return null;
    }

    try {
      _log('发送自定义消息到: $conversationId');

      final jsonStr = jsonEncode(data);
      final createResult = await MessageCreator.createCustomMessage(
        '', // text
        jsonStr, // rawAttachment
      );

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建自定义消息失败: ${createResult.errorDetails}');
        return null;
      }

      final message = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: message,
        conversationId: conversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('自定义消息发送成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('自定义消息发送失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('发送自定义消息异常: $e');
      return null;
    }
  }

  /// 转发消息到指定会话
  Future<TZMessage?> forwardMessage(
    NIMMessage message,
    String toConversationId,
  ) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法转发消息');
      return null;
    }

    try {
      _log('转发消息到: $toConversationId');

      final createResult = await MessageCreator.createForwardMessage(message);

      if (!createResult.isSuccess || createResult.data == null) {
        _log('创建转发消息失败: ${createResult.errorDetails}');
        return null;
      }

      final forwardMsg = createResult.data!;

      final sendResult = await NimCore.instance.messageService.sendMessage(
        message: forwardMsg,
        conversationId: toConversationId,
        params: NIMSendMessageParams(),
      );

      if (sendResult.isSuccess && sendResult.data?.message != null) {
        _log('消息转发成功');
        return _convertToTZMessage(sendResult.data!.message!);
      } else {
        _log('消息转发失败: ${sendResult.errorDetails}');
        return null;
      }
    } catch (e) {
      _log('转发消息异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 查询历史消息
  // ═══════════════════════════════════════════════════════

  /// 获取历史消息列表
  /// [conversationId] 会话 ID
  /// [limit] 每页条数
  /// [anchorMessage] 锚点消息（用于分页加载更早的消息）
  Future<List<TZMessage>> getHistoryMessages(
    String conversationId, {
    int limit = 50,
    NIMMessage? anchorMessage,
  }) async {
    if (!_isIMConnected) {
      _log('IM 未就绪，无法查询历史消息');
      return [];
    }

    try {
      _log('查询历史消息: $conversationId, limit: $limit');

      final option = NIMMessageListOption(
        conversationId: conversationId,
        limit: limit,
        anchorMessage: anchorMessage,
        direction: NIMQueryDirection.desc,
      );

      final result =
          await NimCore.instance.messageService.getMessageList(option: option);

      if (result.isSuccess && result.data != null) {
        final messages = result.data!
            .map((m) => _convertToTZMessage(m))
            .toList()
            .reversed
            .toList(); // 按时间正序排列
        _log('查询到 ${messages.length} 条历史消息');
        return messages;
      } else {
        _log('查询历史消息失败: ${result.errorDetails}');
        return [];
      }
    } catch (e) {
      _log('查询历史消息异常: $e');
      return [];
    }
  }

  /// 根据消息 ID 列表获取消息
  Future<List<TZMessage>> getMessagesByIds(
    List<NIMMessageRefer> messageRefers,
  ) async {
    if (!_isIMConnected) return [];

    try {
      final result = await NimCore.instance.messageService
          .getMessageListByIds(messageRefers: messageRefers);

      if (result.isSuccess && result.data != null) {
        return result.data!.map((m) => _convertToTZMessage(m)).toList();
      }
      return [];
    } catch (e) {
      _log('根据 ID 查询消息异常: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // 消息操作
  // ═══════════════════════════════════════════════════════

  /// 撤回消息
  Future<bool> revokeMessage(NIMMessage message) async {
    if (!_isIMConnected) return false;

    try {
      final result =
          await NimCore.instance.messageService.revokeMessage(message: message);

      if (result.isSuccess) {
        _log('消息撤回成功: ${message.messageClientId}');
        return true;
      }
      _log('消息撤回失败: ${result.errorDetails}');
      return false;
    } catch (e) {
      _log('消息撤回异常: $e');
      return false;
    }
  }

  /// 删除本地消息
  Future<bool> deleteMessage(NIMMessage message) async {
    if (!_isIMConnected) return false;

    try {
      final result = await NimCore.instance.messageService
          .deleteMessage(message: message);

      if (result.isSuccess) {
        _log('消息删除成功: ${message.messageClientId}');
        return true;
      }
      _log('消息删除失败: ${result.errorDetails}');
      return false;
    } catch (e) {
      _log('消息删除异常: $e');
      return false;
    }
  }

  /// 批量删除消息
  Future<bool> deleteMessages(List<NIMMessage> messages) async {
    if (!_isIMConnected || messages.isEmpty) return false;

    try {
      final result = await NimCore.instance.messageService
          .deleteMessages(messages: messages);

      if (result.isSuccess) {
        _log('批量删除消息成功: ${messages.length} 条');
        return true;
      }
      _log('批量删除消息失败: ${result.errorDetails}');
      return false;
    } catch (e) {
      _log('批量删除消息异常: $e');
      return false;
    }
  }

  /// 清空会话历史消息
  Future<bool> clearHistoryMessage(String conversationId) async {
    if (!_isIMConnected) return false;

    try {
      final result = await NimCore.instance.messageService
          .clearHistoryMessage(
        conversationId: conversationId,
        deleteRoam: true,
      );

      if (result.isSuccess) {
        _log('清空历史消息成功: $conversationId');
        return true;
      }
      _log('清空历史消息失败: ${result.errorDetails}');
      return false;
    } catch (e) {
      _log('清空历史消息异常: $e');
      return false;
    }
  }

  /// 发送 P2P 已读回执
  Future<void> sendP2PReadReceipt(NIMMessage message) async {
    if (!_isIMConnected) return;
    try {
      await NimCore.instance.messageService.sendP2PMessageReceipt(message: message);
      _log('P2P 已读回执已发送');
    } catch (e) {
      _log('发送已读回执异常: $e');
    }
  }

  /// 发送群已读回执
  Future<void> sendTeamReadReceipt(List<NIMMessage> messages) async {
    if (!_isIMConnected) return;
    try {
      await NimCore.instance.messageService.sendTeamMessageReceipts(messages: messages);
      _log('群已读回执已发送');
    } catch (e) {
      _log('发送群已读回执异常: $e');
    }
  }

  /// 查询 P2P 已读回执
  Future<bool> isPeerRead(String conversationId) async {
    if (!_isIMConnected) return false;
    try {
      final result = await NimCore.instance.messageService
          .getP2PMessageReceipt(conversationId: conversationId);
      if (result.isSuccess && result.data != null) {
        return true;
      }
      return false;
    } catch (e) {
      _log('查询 P2P 已读回执异常: $e');
      return false;
    }
  }

  /// 复制消息文本到剪贴板
  Future<void> copyMessageText(TZMessage message) async {
    String text = '';
    switch (message.type) {
      case TZMessageType.text:
        text = message.text;
        break;
      case TZMessageType.image:
        text = message.imageUrl ?? '';
        break;
      default:
        text = _getMessagePreview(message.raw!);
        break;
    }
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      _log('消息文本已复制到剪贴板');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 本地消息搜索
  // ═══════════════════════════════════════════════════════

  /// 在指定会话中搜索消息
  Future<List<TZMessage>> searchLocalMessages(
    String conversationId,
    String keyword, {
    int limit = 50,
  }) async {
    if (!_isIMConnected || keyword.isEmpty) return [];

    try {
      _log('搜索本地消息: $conversationId, keyword: $keyword');

      final option = NIMMessageSearchParams(
        keyword: keyword,
        conversationId: conversationId,
        messageLimit: limit,
        sortOrder: NIMSortOrder.desc,
      );

      final result = await NimCore.instance.messageService
          .searchLocalMessages(option: option);

      if (result.isSuccess && result.data != null) {
        final messages = result.data!
            .map((m) => _convertToTZMessage(m))
            .toList();
        _log('搜索到 ${messages.length} 条消息');
        return messages;
      }
      return [];
    } catch (e) {
      _log('搜索本地消息异常: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // 重置
  // ═══════════════════════════════════════════════════════

  /// 重置服务状态（登出时调用）
  void reset() {
    _listenerRegistered = false;
    _receiveMessageSub?.cancel();
    _revokeSub?.cancel();
    _p2pReceiptSub?.cancel();
    _teamReceiptSub?.cancel();
    _receiveMessageSub = null;
    _revokeSub = null;
    _p2pReceiptSub = null;
    _teamReceiptSub = null;
  }

  // ═══════════════════════════════════════════════════════
  // 转换方法
  // ═══════════════════════════════════════════════════════

  /// 将云信消息转换为业务模型
  TZMessage _convertToTZMessage(NIMMessage msg) {
    return TZMessage(
      messageId: msg.messageClientId ?? '',
      conversationId: msg.conversationId ?? '',
      senderId: msg.senderId ?? '',
      senderName: '', // 需要通过 userService 查询
      senderAvatar: '', // 需要通过 userService 查询
      type: _convertMessageType(msg.messageType),
      text: msg.text ?? '',
      imageUrl: _extractImageUrl(msg),
      audioUrl: msg.messageType == NIMMessageType.audio
          ? _extractFileUrl(msg)
          : null,
      audioDuration: _extractAudioDuration(msg),
      videoUrl: msg.messageType == NIMMessageType.video
          ? _extractFileUrl(msg)
          : null,
      videoCoverUrl: _extractVideoCoverUrl(msg),
      videoDuration: _extractVideoDuration(msg),
      fileUrl: msg.messageType == NIMMessageType.file
          ? _extractFileUrl(msg)
          : null,
      fileName: _extractFileName(msg),
      fileSize: _extractFileSize(msg),
      latitude: _extractLatitude(msg),
      longitude: _extractLongitude(msg),
      locationTitle: _extractLocationTitle(msg),
      customData: _extractCustomData(msg),
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.createTime ?? 0),
      status: _convertMessageStatus(msg),
      isRevoked: false,
      raw: msg,
    );
  }

  TZMessageType _convertMessageType(NIMMessageType? type) {
    switch (type) {
      case NIMMessageType.text:
        return TZMessageType.text;
      case NIMMessageType.image:
        return TZMessageType.image;
      case NIMMessageType.audio:
        return TZMessageType.audio;
      case NIMMessageType.video:
        return TZMessageType.video;
      case NIMMessageType.file:
        return TZMessageType.file;
      case NIMMessageType.location:
        return TZMessageType.location;
      case NIMMessageType.custom:
        return TZMessageType.custom;
      case NIMMessageType.notification:
        return TZMessageType.notification;
      case NIMMessageType.tip:
        return TZMessageType.tip;
      default:
        return TZMessageType.unknown;
    }
  }

  TZMessageStatus _convertMessageStatus(NIMMessage msg) {
    switch (msg.sendingState) {
      case NIMMessageSendingState.sending:
        return TZMessageStatus.sending;
      case NIMMessageSendingState.succeeded:
        return TZMessageStatus.success;
      case NIMMessageSendingState.failed:
        return TZMessageStatus.failed;
      default:
        return TZMessageStatus.success;
    }
  }

  /// 提取图片 URL
  String? _extractImageUrl(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageImageAttachment) {
      return attachment.url;
    }
    return null;
  }

  /// 提取文件 URL（通用，适用于音频/视频/文件）
  String? _extractFileUrl(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageFileAttachment) {
      return attachment.url;
    }
    return null;
  }

  /// 提取语音时长
  int? _extractAudioDuration(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageAudioAttachment) {
      return attachment.duration;
    }
    return null;
  }

  /// 提取视频封面 URL
  String? _extractVideoCoverUrl(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageVideoAttachment) {
      return attachment.url; // SDK 自动生成封面
    }
    return null;
  }

  /// 提取视频时长
  int? _extractVideoDuration(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageVideoAttachment) {
      return attachment.duration;
    }
    return null;
  }

  /// 提取文件名
  String? _extractFileName(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageFileAttachment) {
      return attachment.name;
    }
    return null;
  }

  /// 提取文件大小
  int? _extractFileSize(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageFileAttachment) {
      return attachment.size;
    }
    return null;
  }

  /// 提取位置信息
  double? _extractLatitude(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageLocationAttachment) {
      return attachment.latitude;
    }
    return null;
  }

  double? _extractLongitude(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageLocationAttachment) {
      return attachment.longitude;
    }
    return null;
  }

  String? _extractLocationTitle(NIMMessage msg) {
    final attachment = msg.attachment;
    if (attachment is NIMMessageLocationAttachment) {
      return attachment.address;
    }
    return null;
  }

  /// 提取自定义消息数据
  Map<String, dynamic>? _extractCustomData(NIMMessage msg) {
    if (msg.messageType != NIMMessageType.custom) return null;
    final attachment = msg.attachment;
    if (attachment is NIMMessageCustomAttachment) {
      try {
        final raw = attachment.rawAttachment;
        if (raw != null && raw.isNotEmpty) {
          return jsonDecode(raw) as Map<String, dynamic>;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 收到新消息时自动更新会话列表
  void _autoUpdateConversation(NIMMessage msg) {
    try {
      final conversationId = msg.conversationId ?? '';
      if (conversationId.isEmpty) return;

      final senderAccid = msg.senderId ?? '';
      final text = _getMessagePreview(msg);

      // 从 conversationId 解析会话类型和目标 ID
      final parts = conversationId.split('|');
      NIMConversationType type = NIMConversationType.p2p;
      String targetId = conversationId;
      if (parts.length >= 3) {
        targetId = parts[2];
        switch (parts[1]) {
          case '1':
            type = NIMConversationType.p2p;
            break;
          case '2':
            type = NIMConversationType.team;
            break;
          case '3':
            type = NIMConversationType.superTeam;
            break;
        }
      }

      TZConversationService.instance.addOrUpdateLocalConversation(
        conversationId: conversationId,
        type: type,
        targetId: targetId,
        name: senderAccid, // 先用 accid，后续可通过 UserInfoService 更新
        lastMessage: text,
      );
    } catch (e) {
      _log('自动更新会话列表异常: $e');
    }
  }

  /// 获取消息预览文本
  String _getMessagePreview(NIMMessage msg) {
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

  void _log(String message) {
    debugPrint('[ChatMessageService] $message');
  }

  @override
  void dispose() {
    _receiveMessageSub?.cancel();
    _revokeSub?.cancel();
    _p2pReceiptSub?.cancel();
    _teamReceiptSub?.cancel();
    _messageController.close();
    _revokeController.close();
    _progressController.close();
    _statusController.close();
    super.dispose();
  }
}
