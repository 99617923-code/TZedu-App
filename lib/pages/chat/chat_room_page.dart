/// 途正英语 - 聊天室页面（移动端全屏）
/// 火鹰科技出品
///
/// 移动端从聊天列表点击进入的全屏聊天页面
/// 内嵌 ChatPanel 组件，添加返回导航
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';
import 'chat_panel.dart';

class ChatRoomPage extends StatelessWidget {
  final String chatId;

  const ChatRoomPage({super.key, required this.chatId});

  @override
  Widget build(BuildContext context) {
    final chatInfo = mockChatList.where((c) => c.id == chatId).firstOrNull;

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
                            chatInfo?.name ?? '聊天',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TZColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (chatInfo != null)
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
                child: ChatPanel(chatId: chatId),
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
