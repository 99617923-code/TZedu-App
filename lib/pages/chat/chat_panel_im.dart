/// 途正英语 - 聊天面板（真实 IM SDK 版本）
/// 火鹰科技出品
///
/// 对接网易云信 nim_core_v2 SDK：
/// - 真实消息收发（文本/图片/视频/文件）
/// - 历史消息加载
/// - 已读回执
/// - 消息撤回/删除/复制/转发
/// - 图片选择发送
/// - 视频/文件消息气泡
/// - 消息长按菜单
/// - 图片全屏预览
/// - 消息发送失败重发
///
/// 与 ChatPanel（Mock 版）保持一致的 UI 风格
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  List<TZMessage> _messages = [];
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;
  bool _isRecording = false;
  bool _showAttachPanel = false;
  bool _isSendingAttachment = false;
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
    AppNotificationService.instance.setActiveConversation(widget.conversationId);
    // 设置会话服务的活跃会话，避免重复增加未读数
    TZConversationService.instance.setActiveConversation(widget.conversationId);
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
      AppNotificationService.instance.setActiveConversation(widget.conversationId);
      TZConversationService.instance.setActiveConversation(widget.conversationId);
      _messages.clear();
      _hasMoreHistory = true;
      _showAttachPanel = false;
      _loadConversationInfo();
      _loadHistoryMessages();
      _markRead();
    }
  }

  @override
  void dispose() {
    // 清除活跃会话，恢复通知显示
    AppNotificationService.instance.setActiveConversation(null);
    TZConversationService.instance.setActiveConversation(null);
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
      debugPrint('[ChatPanelIM] messageStream 收到 ${messages.length} 条消息');

      // 使用 targetId 匹配而非 conversationId 精确匹配
      final myTargetId = _extractTargetId(widget.conversationId);
      final relevant = messages.where((m) {
        final msgTargetId = _extractTargetId(m.conversationId);
        return m.conversationId == widget.conversationId ||
            msgTargetId == myTargetId ||
            m.senderId == myTargetId;
      }).toList();

      if (relevant.isNotEmpty) {
        debugPrint('[ChatPanelIM] 匹配到 ${relevant.length} 条相关消息');
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
            // 替换为撤回提示
            final revokedMsg = _messages[index];
            _messages[index] = TZMessage(
              messageId: revokedMsg.messageId,
              conversationId: revokedMsg.conversationId,
              senderId: revokedMsg.senderId,
              type: TZMessageType.tip,
              text: revokedMsg.isMine ? '你撤回了一条消息' : '对方撤回了一条消息',
              timestamp: revokedMsg.timestamp,
              isRevoked: true,
            );
          }
        }
      });
    });
  }

  /// 标记已读
  void _markRead() {
    TZConversationService.instance.markConversationRead(widget.conversationId);
  }

  // ═══════════════════════════════════════════════════════
  // 发送消息
  // ═══════════════════════════════════════════════════════

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
      _messages.removeWhere((m) => m.messageId == tempMsg.messageId);
      if (result != null) {
        _messages.add(result);
      } else {
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

    // 同步更新本地会话列表
    if (result != null) {
      _updateLocalConversation(text);
    }
  }

  /// 选择并发送图片
  Future<void> _pickAndSendImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      setState(() => _isSendingAttachment = true);

      // 添加发送中的本地消息
      final tempMsg = TZMessage(
        messageId: 'temp-img-${DateTime.now().millisecondsSinceEpoch}',
        conversationId: widget.conversationId,
        senderId: _myAccid,
        type: TZMessageType.image,
        text: '[图片]',
        timestamp: DateTime.now(),
        status: TZMessageStatus.sending,
      );
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();

      final result = await ChatMessageService.instance.sendImageMessage(
        widget.conversationId,
        pickedFile.path,
      );

      setState(() {
        _messages.removeWhere((m) => m.messageId == tempMsg.messageId);
        if (result != null) {
          _messages.add(result);
          _updateLocalConversation('[图片]');
        } else {
          _messages.add(TZMessage(
            messageId: tempMsg.messageId,
            conversationId: widget.conversationId,
            senderId: _myAccid,
            type: TZMessageType.image,
            text: '[图片发送失败]',
            timestamp: DateTime.now(),
            status: TZMessageStatus.failed,
          ));
        }
        _isSendingAttachment = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[ChatPanelIM] 选择图片异常: $e');
      setState(() => _isSendingAttachment = false);
    }
  }

  /// 选择并发送视频
  Future<void> _pickAndSendVideo() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (pickedFile == null) return;

      setState(() => _isSendingAttachment = true);

      final tempMsg = TZMessage(
        messageId: 'temp-video-${DateTime.now().millisecondsSinceEpoch}',
        conversationId: widget.conversationId,
        senderId: _myAccid,
        type: TZMessageType.video,
        text: '[视频]',
        timestamp: DateTime.now(),
        status: TZMessageStatus.sending,
      );
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();

      final result = await ChatMessageService.instance.sendVideoMessage(
        widget.conversationId,
        pickedFile.path,
      );

      setState(() {
        _messages.removeWhere((m) => m.messageId == tempMsg.messageId);
        if (result != null) {
          _messages.add(result);
          _updateLocalConversation('[视频]');
        } else {
          _messages.add(TZMessage(
            messageId: tempMsg.messageId,
            conversationId: widget.conversationId,
            senderId: _myAccid,
            type: TZMessageType.video,
            text: '[视频发送失败]',
            timestamp: DateTime.now(),
            status: TZMessageStatus.failed,
          ));
        }
        _isSendingAttachment = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[ChatPanelIM] 选择视频异常: $e');
      setState(() => _isSendingAttachment = false);
    }
  }

  /// 选择并发送文件
  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      setState(() => _isSendingAttachment = true);

      final tempMsg = TZMessage(
        messageId: 'temp-file-${DateTime.now().millisecondsSinceEpoch}',
        conversationId: widget.conversationId,
        senderId: _myAccid,
        type: TZMessageType.file,
        text: '[文件]',
        fileName: file.name,
        timestamp: DateTime.now(),
        status: TZMessageStatus.sending,
      );
      setState(() => _messages.add(tempMsg));
      _scrollToBottom();

      final sendResult = await ChatMessageService.instance.sendFileMessage(
        widget.conversationId,
        file.path!,
        displayName: file.name,
      );

      setState(() {
        _messages.removeWhere((m) => m.messageId == tempMsg.messageId);
        if (sendResult != null) {
          _messages.add(sendResult);
          _updateLocalConversation('[文件] ${file.name}');
        } else {
          _messages.add(TZMessage(
            messageId: tempMsg.messageId,
            conversationId: widget.conversationId,
            senderId: _myAccid,
            type: TZMessageType.file,
            text: '[文件发送失败]',
            fileName: file.name,
            timestamp: DateTime.now(),
            status: TZMessageStatus.failed,
          ));
        }
        _isSendingAttachment = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[ChatPanelIM] 选择文件异常: $e');
      setState(() => _isSendingAttachment = false);
    }
  }

  /// 重发失败的消息
  Future<void> _resendMessage(TZMessage msg) async {
    // 移除失败消息
    setState(() {
      _messages.removeWhere((m) => m.messageId == msg.messageId);
    });

    // 根据类型重发
    switch (msg.type) {
      case TZMessageType.text:
        _inputController.text = msg.text;
        await _handleSend();
        break;
      default:
        // 其他类型暂不支持重发
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('该消息类型暂不支持重发'),
              backgroundColor: Color(0xFFF59E0B),
            ),
          );
        }
    }
  }

  /// 更新本地会话列表
  void _updateLocalConversation(String lastMessage) {
    TZConversationService.instance.addOrUpdateLocalConversation(
      conversationId: widget.conversationId,
      type: _isP2P ? NIMConversationType.p2p : NIMConversationType.team,
      targetId: _extractTargetId(widget.conversationId),
      name: _conversationName,
      avatar: _conversationAvatar,
      lastMessage: lastMessage,
    );
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

  // ═══════════════════════════════════════════════════════
  // 消息长按菜单
  // ═══════════════════════════════════════════════════════

  void _showMessageContextMenu(TZMessage msg) {
    if (msg.isRevoked || msg.type == TZMessageType.tip || msg.type == TZMessageType.notification) {
      return;
    }

    final isMine = msg.senderId == _myAccid;
    final canRevoke = isMine &&
        DateTime.now().difference(msg.timestamp).inMinutes < 2 &&
        msg.raw != null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 复制（仅文本消息）
              if (msg.type == TZMessageType.text)
                ListTile(
                  leading: const Icon(Icons.copy, color: Color(0xFF6B7280)),
                  title: const Text('复制'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: msg.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              // 转发
              if (msg.raw != null)
                ListTile(
                  leading: const Icon(Icons.forward, color: Color(0xFF3B82F6)),
                  title: const Text('转发'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showForwardDialog(msg);
                  },
                ),
              // 撤回（2分钟内自己的消息）
              if (canRevoke)
                ListTile(
                  leading: const Icon(Icons.undo, color: Color(0xFFF59E0B)),
                  title: const Text('撤回'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _revokeMessage(msg);
                  },
                ),
              // 删除
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: const Text('删除', style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 撤回消息
  Future<void> _revokeMessage(TZMessage msg) async {
    if (msg.raw == null) return;

    final success = await ChatMessageService.instance.revokeMessage(msg.raw!);
    if (success) {
      setState(() {
        final index = _messages.indexWhere((m) => m.messageId == msg.messageId);
        if (index >= 0) {
          _messages[index] = TZMessage(
            messageId: msg.messageId,
            conversationId: msg.conversationId,
            senderId: msg.senderId,
            type: TZMessageType.tip,
            text: '你撤回了一条消息',
            timestamp: msg.timestamp,
            isRevoked: true,
          );
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('撤回失败，可能已超过2分钟'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  /// 删除消息
  Future<void> _deleteMessage(TZMessage msg) async {
    if (msg.raw != null) {
      await ChatMessageService.instance.deleteMessage(msg.raw!);
    }
    setState(() {
      _messages.removeWhere((m) => m.messageId == msg.messageId);
    });
  }

  /// 转发消息对话框
  void _showForwardDialog(TZMessage msg) {
    final convService = TZConversationService.instance;
    final conversations = convService.conversations
        .where((c) => c.conversationId != widget.conversationId)
        .toList();

    if (conversations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可转发的会话')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '转发到',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 300,
          height: 300,
          child: ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (_, index) {
              final conv = conversations[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: conv.type == NIMConversationType.p2p
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFDCFCE7),
                  child: conv.avatar.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: conv.avatar,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Text(
                              conv.name.isNotEmpty ? conv.name[0] : '?',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                      : Text(
                          conv.name.isNotEmpty ? conv.name[0] : '?',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
                title: Text(
                  conv.name.isNotEmpty ? conv.name : conv.targetId,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (msg.raw != null) {
                    final result = await ChatMessageService.instance
                        .forwardMessage(msg.raw!, conv.conversationId);
                    if (result != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已转发到 ${conv.name}'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
          // 附件面板（暂时隐藏，待相册/拍照/视频/文件功能完善后恢复）
          // AnimatedSize(
          //   duration: const Duration(milliseconds: 200),
          //   curve: Curves.easeInOut,
          //   child: _showAttachPanel ? _buildAttachPanel() : const SizedBox.shrink(),
          // ),
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
          // 搜索消息按钮
          GestureDetector(
            onTap: _showSearchDialog,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
            ),
          ),
          const SizedBox(width: 8),
          // 更多按钮
          GestureDetector(
            onTap: _showChatSettings,
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

  /// 搜索消息对话框
  void _showSearchDialog() {
    final searchController = TextEditingController();
    List<TZMessage> searchResults = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            '搜索消息',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 350,
            height: 400,
            child: Column(
              children: [
                // 搜索输入框
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: '输入关键词搜索...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (keyword) async {
                    if (keyword.trim().isEmpty) return;
                    setDialogState(() => isSearching = true);
                    final results = await ChatMessageService.instance
                        .searchLocalMessages(widget.conversationId, keyword.trim());
                    setDialogState(() {
                      searchResults = results;
                      isSearching = false;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // 搜索结果
                Expanded(
                  child: searchResults.isEmpty
                      ? Center(
                          child: Text(
                            isSearching ? '搜索中...' : '输入关键词后按回车搜索',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (_, index) {
                            final msg = searchResults[index];
                            final userInfo = UserInfoService.instance.getCached(msg.senderId);
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                msg.isMine ? Icons.arrow_upward : Icons.arrow_downward,
                                size: 16,
                                color: msg.isMine
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF3B82F6),
                              ),
                              title: Text(
                                msg.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                '${userInfo?.name ?? msg.senderId} · ${_formatTime(msg.timestamp)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                // 滚动到对应消息
                                final msgIndex = _messages.indexWhere((m) => m.messageId == msg.messageId);
                                if (msgIndex >= 0 && _scrollController.hasClients) {
                                  // 简单的滚动估算
                                  _scrollController.animateTo(
                                    msgIndex * 80.0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                  );
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭', style: TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        ),
      ),
    );
  }

  /// 聊天设置面板
  void _showChatSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  _conversationName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Divider(),
              // 搜索消息
              ListTile(
                leading: const Icon(Icons.search, color: Color(0xFF6B7280)),
                title: const Text('搜索聊天记录'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSearchDialog();
                },
              ),
              // 清空聊天记录
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: Color(0xFFF59E0B)),
                title: const Text('清空聊天记录'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmClearHistory();
                },
              ),
              // 会话免打扰
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined, color: Color(0xFF6B7280)),
                title: const Text('消息免打扰'),
                onTap: () {
                  Navigator.pop(ctx);
                  TZConversationService.instance.toggleMute(widget.conversationId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 确认清空聊天记录
  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空所有聊天记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ChatMessageService.instance
                  .clearHistoryMessage(widget.conversationId);
              if (success) {
                setState(() => _messages.clear());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('清空'),
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
        if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels <= 50 &&
            _hasMoreHistory &&
            !_isLoadingHistory) {
          _loadHistoryMessages();
        }
        return false;
      },
      child: GestureDetector(
        onTap: () {
          // 点击空白区域收起键盘和附件面板
          FocusScope.of(context).unfocus();
          if (_showAttachPanel) {
            setState(() => _showAttachPanel = false);
          }
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
      ),
    );
  }

  Widget _buildTimeSeparator(DateTime time) {
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
            _formatTime(time),
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) {
      return '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMessageBubble(TZMessage msg) {
    final isMine = msg.senderId == _myAccid;
    final userInfo = UserInfoService.instance.getCached(msg.senderId);
    final senderName = userInfo?.name ?? msg.senderName;
    final senderAvatar = userInfo?.avatar ?? msg.senderAvatar;

    return GestureDetector(
      onLongPress: () => _showMessageContextMenu(msg),
      child: Padding(
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
                      child: _buildSendStatus(msg),
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
      case TZMessageType.video:
        return _buildVideoBubble(msg, isMine);
      case TZMessageType.file:
        return _buildFileBubble(msg, isMine);
      case TZMessageType.location:
        return _buildLocationBubble(msg, isMine);
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
      child: SelectableText(
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

    return GestureDetector(
      onTap: () => _showImagePreview(url),
      child: ClipRRect(
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
      ),
    );
  }

  /// 图片全屏预览
  void _showImagePreview(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
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

  /// 视频消息气泡
  Widget _buildVideoBubble(TZMessage msg, bool isMine) {
    return GestureDetector(
      onTap: () {
        // TODO: 播放视频
        final url = msg.videoUrl;
        if (url != null && url.isNotEmpty) {
          debugPrint('[ChatPanelIM] 播放视频: $url');
        }
      },
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 视频封面
            if (msg.videoCoverUrl != null && msg.videoCoverUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: msg.videoCoverUrl!,
                  width: 200,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            // 播放按钮
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
            ),
            // 时长
            if (msg.videoDuration != null && msg.videoDuration! > 0)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(msg.videoDuration!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 文件消息气泡
  Widget _buildFileBubble(TZMessage msg, bool isMine) {
    final fileName = msg.fileName ?? '未知文件';
    final fileSize = msg.fileSize ?? 0;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFFF5F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
          // 文件图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getFileIconColor(fileName).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getFileIcon(fileName),
              color: _getFileIconColor(fileName),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize > 0)
                  Text(
                    _formatFileSize(fileSize),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 位置消息气泡
  Widget _buildLocationBubble(TZMessage msg, bool isMine) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFFF5F3FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg.locationTitle ?? '位置信息',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A2E),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

  Widget _buildSendStatus(TZMessage msg) {
    if (msg.status == TZMessageStatus.sending) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    if (msg.status == TZMessageStatus.failed) {
      return GestureDetector(
        onTap: () => _resendMessage(msg),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: Color(0xFFEF4444)),
            SizedBox(width: 4),
            Text(
              '发送失败，点击重试',
              style: TextStyle(fontSize: 10, color: Color(0xFFEF4444)),
            ),
          ],
        ),
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
          // 附件发送中提示
          if (_isSendingAttachment)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '正在发送...',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7C3AED)),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              // 表情按钮
              _buildInputButton(Icons.emoji_emotions_outlined, const Color(0xFF6B7280), () {
                // TODO: 表情面板
              }),
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
                    maxLines: 4,
                    minLines: 1,
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
              // 附件按钮（+号）— 暂时隐藏，待相册/拍照/视频/文件功能完善后恢复
              // const SizedBox(width: 8),
              // _buildInputButton(
              //   _showAttachPanel ? Icons.close : Icons.add_circle_outline,
              //   _showAttachPanel ? const Color(0xFFEF4444) : const Color(0xFF7C3AED),
              //   () => setState(() => _showAttachPanel = !_showAttachPanel),
              // ),
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

  /// 附件面板（图片、视频、文件）
  Widget _buildAttachPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildAttachItem(
            icon: Icons.photo_library,
            label: '相册',
            color: const Color(0xFF3B82F6),
            onTap: () {
              setState(() => _showAttachPanel = false);
              _pickAndSendImage(source: ImageSource.gallery);
            },
          ),
          _buildAttachItem(
            icon: Icons.camera_alt,
            label: '拍照',
            color: const Color(0xFF10B981),
            onTap: () {
              setState(() => _showAttachPanel = false);
              _pickAndSendImage(source: ImageSource.camera);
            },
          ),
          _buildAttachItem(
            icon: Icons.videocam,
            label: '视频',
            color: const Color(0xFFF59E0B),
            onTap: () {
              setState(() => _showAttachPanel = false);
              _pickAndSendVideo();
            },
          ),
          _buildAttachItem(
            icon: Icons.insert_drive_file,
            label: '文件',
            color: const Color(0xFF7C3AED),
            onTap: () {
              setState(() => _showAttachPanel = false);
              _pickAndSendFile();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
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

  // ═══════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return const Color(0xFFEF4444);
      case 'doc':
      case 'docx':
        return const Color(0xFF3B82F6);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF10B981);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }
}
