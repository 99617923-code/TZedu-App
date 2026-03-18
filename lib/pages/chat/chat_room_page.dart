/// 途正英语 - 聊天室页面（移动端全屏）
/// 火鹰科技出品
///
/// 移动端从聊天列表点击进入的全屏聊天页面
/// 支持两种模式：
/// - 真实 IM 模式：传入 conversationId，使用 ChatPanelIM
/// - Mock 模式：传入 chatId，使用 ChatPanel
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';
import 'chat_panel.dart';
import 'chat_panel_im.dart';

class ChatRoomPage extends StatelessWidget {
  /// Mock 模式使用
  final String? chatId;

  /// 真实 IM 模式使用
  final String? conversationId;
  final String? conversationName;

  const ChatRoomPage({
    super.key,
    this.chatId,
    this.conversationId,
    this.conversationName,
  }) : assert(chatId != null || conversationId != null);

  bool get _isIMMode => conversationId != null;

  @override
  Widget build(BuildContext context) {
    // Mock 模式下获取聊天信息
    final chatInfo = chatId != null
        ? mockChatList.where((c) => c.id == chatId).firstOrNull
        : null;

    final title = _isIMMode
        ? (conversationName ?? '聊天')
        : (chatInfo?.name ?? '聊天');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [
              TZColors.bgStart,
              TZColors.bgMid,
              TZColors.bgEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 移动端顶部导航栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                      color: TZColors.textDark,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TZColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!_isIMMode && chatInfo != null)
                            Text(
                              _getSubtitle(chatInfo),
                              style: TextStyle(
                                fontSize: 11,
                                color: chatInfo.isOnline
                                    ? const Color(0xFF10B981)
                                    : TZColors.textLight,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert, size: 20),
                      color: TZColors.textGray,
                    ),
                  ],
                ),
              ),
              // 聊天面板
              Expanded(
                child: _isIMMode
                    ? ChatPanelIM(conversationId: conversationId!)
                    : ChatPanel(chatId: chatId!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSubtitle(ChatItem info) {
    switch (info.type) {
      case ChatItemType.direct:
        return info.isOnline ? '在线' : '离线';
      case ChatItemType.group:
        return '${info.memberCount ?? 0}人';
      case ChatItemType.feature:
        return info.featureDesc ?? '';
      default:
        return '';
    }
  }
}
