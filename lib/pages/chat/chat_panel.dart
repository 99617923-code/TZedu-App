/// 途正英语 - 聊天面板（桌面端右侧 / 聊天室内嵌）
/// 火鹰科技出品
///
/// 支持：单聊/群聊 + AI教练自动评分英文表达
/// 特色：违禁词过滤、杨妈数字人自动回复、智能客服
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';

class ChatPanel extends StatefulWidget {
  final String chatId;

  const ChatPanel({super.key, required this.chatId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late List<ChatMessage> _messages;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showAICoach = true;
  bool _isRecording = false;
  String? _expandedAnalysisId;

  ChatItem? get _chatInfo =>
      mockChatList.where((c) => c.id == widget.chatId).firstOrNull;

  bool get _isYangma => widget.chatId == 'yangma-digital';
  bool get _isSmartCS => widget.chatId == 'smart-cs';

  @override
  void initState() {
    super.initState();
    _messages = List.from(mockChatMessages[widget.chatId] ?? []);
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _messages = List.from(mockChatMessages[widget.chatId] ?? []);
      _inputController.clear();
      _expandedAnalysisId = null;
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    // 安全过滤
    final result = filterMessage(text);
    if (result.warnings.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warnings.join('；')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final isEng = isEnglishText(result.filtered);
    final newMsg = ChatMessage(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      senderId: 's1',
      senderName: '我',
      senderAvatar: '',
      senderRole: SenderRole.student,
      type: MessageType.text,
      content: result.filtered,
      timestamp: DateTime.now(),
      isEnglish: isEng,
    );

    setState(() {
      _messages.add(newMsg);
      _inputController.clear();
    });
    _scrollToBottom();

    // AI 教练评分（英文消息）
    if (isEng && _showAICoach) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final aiMsg = ChatMessage(
          id: 'msg-ai-${DateTime.now().millisecondsSinceEpoch}',
          senderId: 'ai',
          senderName: 'AI 教练',
          senderAvatar: '',
          senderRole: SenderRole.ai,
          type: MessageType.aiCoach,
          content: '',
          timestamp: DateTime.now(),
          aiAnalysis: generateMockAnalysis(text),
        );
        setState(() => _messages.add(aiMsg));
        _scrollToBottom();
      });
    }

    // 杨妈自动回复
    if (_isYangma) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        final reply = yangmaReplies[Random().nextInt(yangmaReplies.length)];
        final yangmaMsg = ChatMessage(
          id: 'msg-ym-${DateTime.now().millisecondsSinceEpoch}',
          senderId: 'yangma',
          senderName: '杨妈',
          senderAvatar: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=100&h=100&fit=crop',
          senderRole: SenderRole.ai,
          type: MessageType.text,
          content: reply,
          timestamp: DateTime.now(),
        );
        setState(() => _messages.add(yangmaMsg));
        _scrollToBottom();
      });
    }

    // 智能客服回复
    if (_isSmartCS) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final lowerInput = result.filtered.toLowerCase();
        String reply = csDefaultReply;
        for (final entry in csReplies.entries) {
          if (lowerInput.contains(entry.key)) {
            reply = entry.value;
            break;
          }
        }
        final csMsg = ChatMessage(
          id: 'msg-cs-${DateTime.now().millisecondsSinceEpoch}',
          senderId: 'smart-cs',
          senderName: '途正智能客服',
          senderAvatar: '',
          senderRole: SenderRole.ai,
          type: MessageType.text,
          content: reply,
          timestamp: DateTime.now(),
        );
        setState(() => _messages.add(csMsg));
        _scrollToBottom();
      });
    }
  }

  ({String title, String subtitle}) _getChatTitle() {
    final info = _chatInfo;
    if (info == null) return (title: '聊天', subtitle: '');
    switch (info.type) {
      case ChatItemType.direct:
        return (title: info.name, subtitle: info.isOnline ? '在线' : '离线');
      case ChatItemType.group:
        return (title: info.name, subtitle: '${info.memberCount ?? 0}人');
      case ChatItemType.feature:
        return (title: info.name, subtitle: info.featureDesc ?? '');
      case ChatItemType.activity:
        return (title: info.name, subtitle: info.activityTime ?? '');
      default:
        return (title: info.name, subtitle: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatTitle = _getChatTitle();

    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: [
          // ═══ 顶部标题栏 ═══
          _buildHeader(chatTitle.title, chatTitle.subtitle),
          // ═══ AI教练提示条 ═══
          if (_showAICoach) _buildAICoachBanner(),
          // ═══ 消息列表 ═══
          Expanded(child: _buildMessageList()),
          // ═══ 底部输入栏 ═══
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _isYangma ? const Color(0xFFFFF7ED) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: _isYangma ? const Color(0xFFFED7AA) : const Color(0xFFF3F4F6),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isYangma) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '数字人',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _isYangma ? '🟢 在线 · 杨妈AI数字人 · 练英语/问课程' : subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: _isYangma
                          ? const Color(0xFFF97316)
                          : (_chatInfo?.isOnline == true
                              ? const Color(0xFF10B981)
                              : const Color(0xFF9CA3AF)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // AI 教练开关
          GestureDetector(
            onTap: () => setState(() => _showAICoach = !_showAICoach),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _showAICoach ? const Color(0xFFF5F3FF) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _showAICoach ? const Color(0xFFDDD6FE) : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 14,
                    color: _showAICoach ? TZColors.primaryPurple : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _showAICoach ? TZColors.primaryPurple : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 更多按钮
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.more_vert, size: 18, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  Widget _buildAICoachBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F3FF),
        border: Border(bottom: BorderSide(color: Color(0xFFE9E5FF))),
      ),
      child: const Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 14, color: Color(0xFF7C3AED)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI教练已开启 · 用英文发消息将自动获得语法、词汇、表达评分',
              style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _renderMessage(msg),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // 消息渲染
  // ═══════════════════════════════════════════════════════

  Widget _renderMessage(ChatMessage msg) {
    switch (msg.type) {
      case MessageType.system:
        return _renderSystemMessage(msg);
      case MessageType.aiCoach:
        return _renderAIAnalysis(msg);
      case MessageType.correction:
        return _renderCorrectionMessage(msg);
      default:
        return _renderTextMessage(msg);
    }
  }

  Widget _renderSystemMessage(ChatMessage msg) {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          msg.content,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _renderTextMessage(ChatMessage msg) {
    final isMe = msg.senderId == 's1';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 发送者信息（非自己）
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSmallAvatar(msg.senderAvatar, msg.senderName),
                    const SizedBox(width: 6),
                    Text(
                      msg.senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    if (msg.senderRole == SenderRole.foreignTeacher) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '外教',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // 消息气泡
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: isMe ? null : const EdgeInsets.only(left: 32),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF7C3AED) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : const Color(0xFF1A1A2E),
                  height: 1.5,
                ),
              ),
            ),
            // 英文标记
            if (isMe && msg.isEnglish)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 10, color: const Color(0xFF9CA3AF)),
                    const SizedBox(width: 2),
                    const Text(
                      'EN · AI评分中...',
                      style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _renderCorrectionMessage(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSmallAvatar(msg.senderAvatar, msg.senderName),
                const SizedBox(width: 6),
                Text(msg.senderName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('外教建议', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.only(left: 32),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Text(
                msg.content,
                style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E), height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderAIAnalysis(ChatMessage msg) {
    if (msg.aiAnalysis == null) return const SizedBox.shrink();
    final a = msg.aiAnalysis!;
    final isExpanded = _expandedAnalysisId == msg.id;
    final scoreColor = a.score >= 7
        ? const Color(0xFF10B981)
        : a.score >= 5
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9E5FF)),
          ),
          child: Column(
            children: [
              // 头部（可点击展开）
              GestureDetector(
                onTap: () => setState(() {
                  _expandedAnalysisId = isExpanded ? null : msg.id;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7C3AED),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.smart_toy, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'AI 教练',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED)),
                      ),
                      const Spacer(),
                      Text(
                        '${a.score}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: scoreColor),
                      ),
                      const Text('/10', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
              ),
              // 鼓励语
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    a.encouragement,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
              ),
              // 展开详情
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: isExpanded
                    ? Container(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0xFFE9E5FF))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            // 三维评分
                            Row(
                              children: [
                                _buildScoreCard('语法', a.grammar.score, Icons.check_circle_outline),
                                const SizedBox(width: 8),
                                _buildScoreCard('词汇', a.vocabulary.score, Icons.emoji_events_outlined),
                                const SizedBox(width: 8),
                                _buildScoreCard('表达', a.expression.score, Icons.lightbulb_outline),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // 语法建议
                            if (a.grammar.issues.isNotEmpty) ...[
                              const Text('📝 语法建议', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                              const SizedBox(height: 4),
                              ...a.grammar.issues.map((issue) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text('• $issue', style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563), height: 1.4)),
                              )),
                              const SizedBox(height: 8),
                            ],
                            // 词汇水平
                            const Text('📚 词汇水平', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                a.vocabulary.level,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // 表达建议
                            const Text('💡 表达建议', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                            const SizedBox(height: 4),
                            Text(a.expression.suggestion, style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563), height: 1.4)),
                            const SizedBox(height: 8),
                            // 参考表达
                            if (a.correctedText.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFD1FAE5)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('✅ 参考表达', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                                    const SizedBox(height: 4),
                                    Text(
                                      a.correctedText,
                                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF047857), height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(String label, int score, IconData icon) {
    final color = score >= 7
        ? const Color(0xFF10B981)
        : score >= 5
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: const Color(0xFF7C3AED)),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED))),
              ],
            ),
            const SizedBox(height: 4),
            Text('$score', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          ],
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
                      hintText: '输入消息... (英文自动AI评分)',
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
              _buildInputButton(Icons.image_outlined, const Color(0xFF6B7280), () {}),
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

  Widget _buildSmallAvatar(String url, String name) {
    if (url.isEmpty) {
      return Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFF7C3AED),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0] : '?',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(width: 24, height: 24, color: const Color(0xFFF3F4F6)),
        errorWidget: (_, __, ___) => Container(
          width: 24,
          height: 24,
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.person, size: 14, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }
}
