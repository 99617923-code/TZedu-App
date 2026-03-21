/// 途正英语 - 聊天面板（真实 IM SDK 版本）
/// 火鹰科技出品
///
/// 对接网易云信 nim_core_v2 SDK：
/// - 真实消息收发
/// - 历史消息加载
/// - 已读回执
/// - 消息撤回
/// - 图片/语音/文件消息
///
/// 与 ChatPanel（Mock 版）保持一致的 UI 风格
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../../config/theme.dart';
import '../../services/im_service.dart';
import '../../services/chat_message_service.dart';
import '../../services/user_info_service.dart';
import '../../services/conversation_service.dart';
import '../../services/notification_service.dart';

class ChatPanelIM extends StatefulWidget {
  final String conversationId;

  const ChatPanelIM({super.key, required this.conversationId});

  @override
  State<ChatPanelIM> createState() => _ChatPanelIMState();
}

class _ChatPanelIMState extends State<ChatPanelIM> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<TZMessage> _messages = [];
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;
  bool _isRecording = false;
  StreamSubscription? _messageSub;
  StreamSubscription? _revokeSub;

  String get _myAccid => IMService.instance.currentAccid ?? '';

  /// 从 conversationId 中提取 targetId
  /// conversationId 格式: {appId}|{type}|{targetId}
  String _extractTargetId(String conversationId) {
    final parts = conversationId.split('|');
    return parts.length >= 3 ? parts[2] : conversationId;
  }

  // 会话信息
  String _conversationName = '';
  String _conversationAvatar = '';
  bool _isP2P = true;

  @override
  void initState() {
    super.initState();
    // 设置当前活跃会话，避免弹出当前会话的通知
    NotificationService.instance.setActiveConversation(widget.conversationId);
    _loadConversationInfo();
    _loadHistoryMessages();
    _listenNewMessages();
    _markRead();
  }

  @override
  void didUpdateWidget(ChatPanelIM oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      // 更新活跃会话
      NotificationService.instance.setActiveConversation(widget.conversationId);
      _messages.clear();
      _hasMoreHistory = true;
      _loadConversationInfo();
      _loadHistoryMessages();
      _markRead();
    }
  }

  @override
  void dispose() {
    // 清除活跃会话，恢复通知显示
    NotificationService.instance.setActiveConversation(null);
    _inputController.dispose();
    _scrollController.dispose();
    _messageSub?.cancel();
    _revokeSub?.cancel();
    super.dispose();
  }

  /// 加载会话信息
  void _loadConversationInfo() {
    final convService = TZConversationService.instance;
    final conv = convService.conversations
        .where((c) => c.conversationId == widget.conversationId)
        .firstOrNull;

    if (conv != null) {
      _conversationName = conv.name.isNotEmpty ? conv.name : conv.targetId;
      _conversationAvatar = conv.avatar;
      _isP2P = conv.type == NIMConversationType.p2p;
    }
  }

  /// 加载历史消息
  Future<void> _loadHistoryMessages() async {
    if (_isLoadingHistory || !_hasMoreHistory) return;

    setState(() => _isLoadingHistory = true);

    try {
      final messages = await ChatMessageService.instance.getHistoryMessages(
        widget.conversationId,
        limit: 50,
        anchorMessage: _messages.isNotEmpty ? _messages.first.raw : null,
      );

      if (messages.isEmpty) {
        _hasMoreHistory = false;
      } else {
        // 加载用户信息
        final senderIds = messages.map((m) => m.senderId).toSet().toList();
        await UserInfoService.instance.getUserInfoBatch(senderIds);

        setState(() {
          if (_messages.isEmpty) {
            _messages = messages;
          } else {
            _messages.insertAll(0, messages);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('[ChatPanelIM] 加载历史消息异常: $e');
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  /// 监听新消息
  void _listenNewMessages() {
    _messageSub = ChatMessageService.instance.messageStream.listen((messages) {
      final relevant = messages
          .where((m) => m.conversationId == widget.conversationId)
          .toList();

      if (relevant.isNotEmpty) {
        setState(() => _messages.addAll(relevant));
        _scrollToBottom();
        _markRead();
      }
    });

    _revokeSub = ChatMessageService.instance.revokeStream.listen((ids) {
      setState(() {
        for (final id in ids) {
          final index = _messages.indexWhere((m) => m.messageId == id);
          if (index >= 0) {
            _messages.removeAt(index);
          }
        }
      });
    });
  }

  /// 标记已读
  void _markRead() {
    TZConversationService.instance.markConversationRead(widget.conversationId);
  }

  /// 发送文本消息
  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    setState(() {}); // 更新发送按钮状态

    // 先添加一个 "发送中" 的本地消息
    final tempMsg = TZMessage(
      messageId: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.conversationId,
      senderId: _myAccid,
      senderName: '我',
      type: TZMessageType.text,
      text: text,
      timestamp: DateTime.now(),
      status: TZMessageStatus.sending,
    );

    setState(() => _messages.add(tempMsg));
    _scrollToBottom();

    // 通过 SDK 发送
    final result = await ChatMessageService.instance
        .sendTextMessage(widget.conversationId, text);

    setState(() {
      // 移除临时消息
      _messages.removeWhere((m) => m.messageId == tempMsg.messageId);
      // 添加真实消息
      if (result != null) {
        _messages.add(result);
      } else {
        // 发送失败，标记为失败状态
        _messages.add(TZMessage(
          messageId: tempMsg.messageId,
          conversationId: widget.conversationId,
          senderId: _myAccid,
          senderName: '我',
          type: TZMessageType.text,
          text: text,
          timestamp: DateTime.now(),
          status: TZMessageStatus.failed,
        ));
      }
    });
    _scrollToBottom();

    // 同步更新本地会话列表的最后一条消息（桌面端本地会话管理需要）
    if (result != null) {
      TZConversationService.instance.addOrUpdateLocalConversation(
        conversationId: widget.conversationId,
        type: _isP2P ? NIMConversationType.p2p : NIMConversationType.team,
        targetId: _extractTargetId(widget.conversationId),
        name: _conversationName,
        avatar: _conversationAvatar,
        lastMessage: text,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: [
          // ═══ 顶部标题栏 ═══
          _buildHeader(),
          // ═══ 消息列表 ═══
          Expanded(child: _buildMessageList()),
          // ═══ 底部输入栏 ═══
          _buildInputBar(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 顶部标题栏
  // ═══════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isP2P
                  ? const Color(0xFFDBEAFE)
                  : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _conversationAvatar.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: _conversationAvatar,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                        _isP2P ? Icons.person : Icons.group,
                        size: 18,
                        color: _isP2P
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF10B981),
                      ),
                    ),
                  )
                : Icon(
                    _isP2P ? Icons.person : Icons.group,
                    size: 18,
                    color: _isP2P
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF10B981),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _conversationName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isP2P ? '私聊' : '群聊',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          // 更多按钮
          GestureDetector(
            onTap: () {
              // TODO: 聊天设置面板
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 消息列表
  // ═══════════════════════════════════════════════════════

  Widget _buildMessageList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 滚动到顶部时加载更多历史消息
        if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels <= 50 &&
            _hasMoreHistory &&
            !_isLoadingHistory) {
          _loadHistoryMessages();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _messages.length + (_isLoadingHistory ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isLoadingHistory && index == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final msgIndex = _isLoadingHistory ? index - 1 : index;
          final msg = _messages[msgIndex];

          // 时间分隔线
          Widget? timeWidget;
          if (msgIndex == 0 ||
              msg.timestamp
                      .difference(_messages[msgIndex - 1].timestamp)
                      .inMinutes >
                  5) {
            timeWidget = _buildTimeSeparator(msg.timestamp);
          }

          return Column(
            children: [
              if (timeWidget != null) timeWidget,
              _buildMessageBubble(msg),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimeSeparator(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    String text;

    if (diff.inMinutes < 1) {
      text = '刚刚';
    } else if (diff.inHours < 1) {
      text = '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      text = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      text = '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      text = '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(TZMessage msg) {
    final isMine = msg.senderId == _myAccid;
    final userInfo = UserInfoService.instance.getCached(msg.senderId);
    final senderName = userInfo?.name ?? msg.senderName;
    final senderAvatar = userInfo?.avatar ?? msg.senderAvatar;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            _buildAvatar(senderAvatar, senderName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 发送者名称（群聊中显示）
                if (!isMine && !_isP2P)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      senderName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                // 消息内容
                _buildMessageContent(msg, isMine),
                // 发送状态
                if (isMine && msg.status != TZMessageStatus.success)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _buildSendStatus(msg.status),
                  ),
              ],
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 8),
            _buildAvatar(senderAvatar, senderName),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageContent(TZMessage msg, bool isMine) {
    switch (msg.type) {
      case TZMessageType.text:
        return _buildTextBubble(msg.text, isMine);
      case TZMessageType.image:
        return _buildImageBubble(msg);
      case TZMessageType.audio:
        return _buildAudioBubble(msg, isMine);
      case TZMessageType.notification:
      case TZMessageType.tip:
        return _buildSystemTip(msg.text);
      default:
        return _buildTextBubble('[${msg.type.name}]', isMine);
    }
  }

  Widget _buildTextBubble(String text, bool isMine) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine
            ? const Color(0xFF7C3AED)
            : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMine ? 16 : 4),
          topRight: Radius.circular(isMine ? 4 : 16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: isMine ? Colors.white : const Color(0xFF1A1A2E),
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildImageBubble(TZMessage msg) {
    final url = msg.imageUrl;
    if (url == null || url.isEmpty) {
      return _buildTextBubble('[图片]', msg.isMine);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.5,
          maxHeight: 200,
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 150,
            height: 100,
            color: const Color(0xFFF3F4F6),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => Container(
            width: 150,
            height: 100,
            color: const Color(0xFFF3F4F6),
            child: const Icon(Icons.broken_image, color: Color(0xFF9CA3AF)),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioBubble(TZMessage msg, bool isMine) {
    final duration = msg.audioDuration ?? 0;
    final width = 80.0 + (duration * 3).clamp(0, 120).toDouble();

    return GestureDetector(
      onTap: () {
        // TODO: 播放语音
      },
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? const Color(0xFF7C3AED)
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isMine ? 16 : 4),
            topRight: Radius.circular(isMine ? 4 : 16),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              size: 18,
              color: isMine ? Colors.white : const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 4),
            // 语音波形动画（静态）
            ...List.generate(3, (i) => Container(
              width: 3,
              height: 8.0 + (i * 4),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: (isMine ? Colors.white : const Color(0xFF7C3AED)).withOpacity(0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const Spacer(),
            Text(
              '${duration}″',
              style: TextStyle(
                fontSize: 12,
                color: isMine ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemTip(String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  Widget _buildSendStatus(TZMessageStatus status) {
    if (status == TZMessageStatus.sending) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    if (status == TZMessageStatus.failed) {
      return GestureDetector(
        onTap: () {
          // TODO: 重发消息
        },
        child: const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildAvatar(String url, String name) {
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _buildDefaultAvatar(name),
        ),
      );
    }
    return _buildDefaultAvatar(name);
  }

  Widget _buildDefaultAvatar(String name) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 输入栏
  // ═══════════════════════════════════════════════════════

  Widget _buildInputBar() {
    final hasText = _inputController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 表情按钮
              _buildInputButton(Icons.emoji_emotions_outlined, const Color(0xFF6B7280), () {}),
              const SizedBox(width: 8),
              // 输入框
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasText ? const Color(0xFFDDD6FE) : const Color(0xFFF3F4F6),
                      width: 2,
                    ),
                  ),
                  child: TextField(
                    controller: _inputController,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 发送/录音按钮
              if (hasText)
                GestureDetector(
                  onTap: _handleSend,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.send, size: 18, color: Colors.white),
                  ),
                )
              else
                GestureDetector(
                  onLongPressStart: (_) => setState(() => _isRecording = true),
                  onLongPressEnd: (_) => setState(() => _isRecording = false),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _isRecording ? const Color(0xFFEF4444) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.mic,
                      size: 18,
                      color: _isRecording ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // 图片按钮
              _buildInputButton(Icons.image_outlined, const Color(0xFF6B7280), () {
                // TODO: 选择图片发送
              }),
            ],
          ),
          // 录音提示
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '正在录音... 松开发送',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
