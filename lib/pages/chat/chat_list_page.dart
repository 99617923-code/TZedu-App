/// 途正英语 - 聊天列表页面（对标HelloTalk）
/// 火鹰科技出品
///
/// 移动端：单列聊天列表，点击跳转到 ChatRoom 页面
/// 桌面端：微信桌面版左右分栏布局（左侧聊天列表 + 右侧聊天内容）
///
/// 数据来源：
/// - 已登录 IM：从 TZConversationService 获取真实会话数据
/// - 未登录 IM：显示 Mock 数据（开发/演示模式）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';
import '../../utils/responsive.dart';
import '../../services/im_service.dart';
import '../../services/conversation_service.dart';
import 'chat_panel.dart';
import 'chat_panel_im.dart';
import 'chat_room_page.dart';
import 'widgets/chat_item_card.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  String _activeFilter = 'all';
  String _searchQuery = '';
  bool _showSearch = false;
  String? _selectedChatId;
  String? _selectedConversationId;
  final TextEditingController _searchController = TextEditingController();

  /// 是否使用真实 IM 数据
  bool get _useRealIM => context.read<IMService>().isLoggedIn;

  // ═══════════════════════════════════════════════════════
  // Mock 数据模式（未登录 IM 时使用）
  // ═══════════════════════════════════════════════════════

  List<ChatItem> get _filteredMockChats {
    return mockChatList.where((c) {
      if (_activeFilter != 'all') {
        final filterType = chatFilters.firstWhere((f) => f.key == _activeFilter).type;
        if (filterType != null && c.type != filterType) return false;
      }
      if (_searchQuery.isNotEmpty) {
        return c.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList()
      ..sort((a, b) {
        if (a.pinned && !b.pinned) return -1;
        if (!a.pinned && b.pinned) return 1;
        return 0;
      });
  }

  int _getFilterCount(ChatFilter filter) {
    if (filter.type == null) return mockChatList.length;
    return mockChatList.where((c) => c.type == filter.type).length;
  }

  // ═══════════════════════════════════════════════════════
  // 真实 IM 数据模式
  // ═══════════════════════════════════════════════════════

  List<TZConversation> get _filteredIMConversations {
    final convService = context.read<TZConversationService>();
    var list = convService.conversations;

    // 按类型筛选
    if (_activeFilter == 'direct') {
      list = list.where((c) => c.type == NIMConversationType.p2p).toList();
    } else if (_activeFilter == 'group') {
      list = list.where((c) => c.type == NIMConversationType.team || c.type == NIMConversationType.superTeam).toList();
    }

    // 搜索
    if (_searchQuery.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    return list;
  }

  // ═══════════════════════════════════════════════════════
  // 点击事件
  // ═══════════════════════════════════════════════════════

  void _onMockChatTap(ChatItem chat) {
    final isDesktop = Responsive.isDesktop(context);
    if (isDesktop) {
      setState(() {
        _selectedChatId = chat.id;
        _selectedConversationId = null;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomPage(chatId: chat.id),
        ),
      );
    }
  }

  void _onIMConversationTap(TZConversation conv) {
    final isDesktop = Responsive.isDesktop(context);

    // 标记已读
    TZConversationService.instance.markConversationRead(conv.conversationId);

    if (isDesktop) {
      setState(() {
        _selectedConversationId = conv.conversationId;
        _selectedChatId = null;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomPage(
            conversationId: conv.conversationId,
            conversationName: conv.name,
          ),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // 发起新聊天
  // ═══════════════════════════════════════════════════════

  /// 显示发起新聊天对话框
  void _showNewChatDialog() {
    final imService = context.read<IMService>();
    if (!imService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('IM 未连接，请先登录'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final accidController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: Color(0xFF7C3AED), size: 24),
            SizedBox(width: 8),
            Text(
              '发起新聊天',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入对方的 IM 账号（accid）即可直接发起私聊',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: accidController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '例如: tz_user_123',
                hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
                prefixIcon: const Icon(Icons.person_search, color: Color(0xFF7C3AED)),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _startP2PChat(value.trim());
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              '当前账号: ${imService.currentAccid ?? "未知"}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final accid = accidController.text.trim();
              if (accid.isNotEmpty) {
                Navigator.of(ctx).pop();
                _startP2PChat(accid);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('开始聊天', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// 通过 accid 发起 P2P 聊天
  Future<void> _startP2PChat(String targetAccid) async {
    try {
      // 使用 NIM SDK 的 ConversationIdUtil 生成 P2P 会话ID
      final result = await NimCore.instance.conversationIdUtil
          .p2pConversationId(targetAccid);

      if (!result.isSuccess || result.data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('创建会话失败: ${result.errorDetails ?? "未知错误"}'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      final conversationId = result.data!;
      debugPrint('[ChatListPage] 发起 P2P 聊天: $targetAccid -> $conversationId');

      if (!mounted) return;

      final isDesktop = Responsive.isDesktop(context);

      if (isDesktop) {
        // 桌面端：直接在右侧面板打开
        setState(() {
          _selectedConversationId = conversationId;
          _selectedChatId = null;
        });
      } else {
        // 移动端：跳转到聊天室页面
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(
              conversationId: conversationId,
              conversationName: targetAccid,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ChatListPage] 发起聊天异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发起聊天失败: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  // ═══════════════════════════════════════════════════════
  // 桌面端：左右分栏布局
  // ═══════════════════════════════════════════════════════

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // 左侧聊天列表面板
        Container(
          width: 380,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.5, -1),
              end: Alignment(0.5, 1),
              colors: [
                Color(0xFFF5F3FF),
                Color(0xFFF8F7FF),
                Color(0xFFF9FAFB),
              ],
            ),
            border: Border(
              right: BorderSide(color: Color(0xFFE9E5FF), width: 1),
            ),
          ),
          child: Column(
            children: [
              _buildListHeader(),
              Expanded(
                child: _buildChatListContent(),
              ),
            ],
          ),
        ),
        // 右侧内容面板
        Expanded(
          child: _buildRightPanel(),
        ),
      ],
    );
  }

  Widget _buildRightPanel() {
    // 优先显示真实 IM 聊天面板
    if (_selectedConversationId != null) {
      return ChatPanelIM(
        key: ValueKey(_selectedConversationId),
        conversationId: _selectedConversationId!,
      );
    }
    // 回退到 Mock 聊天面板
    if (_selectedChatId != null) {
      return ChatPanel(
        key: ValueKey(_selectedChatId),
        chatId: _selectedChatId!,
      );
    }
    return _buildEmptyPanel();
  }

  Widget _buildEmptyPanel() {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFFE5E7EB)),
            SizedBox(height: 16),
            Text(
              '选择一个聊天开始对话',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 移动端：单列布局
  // ═══════════════════════════════════════════════════════

  Widget _buildMobileLayout() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.5, -1),
          end: Alignment(0.5, 1),
          colors: [
            TZColors.bgStart,
            TZColors.bgPurple,
            TZColors.bgMid,
            TZColors.bgEnd,
          ],
          stops: [0.0, 0.15, 0.4, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildListHeader(),
            Expanded(
              child: _buildChatListContent(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 共享组件
  // ═══════════════════════════════════════════════════════

  Widget _buildListHeader() {
    final imService = context.watch<IMService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // 标题行
          Row(
            children: [
              const Text(
                '消息',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: TZColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              // IM 连接状态指示
              _buildConnectionIndicator(imService.connectionStatus),
              const Spacer(),
              // 搜索按钮
              _buildIconButton(
                icon: Icons.search,
                color: const Color(0xFF6B7280),
                bgColor: const Color(0xFFF3F4F6),
                onTap: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                }),
              ),
              const SizedBox(width: 8),
              // 新建按钮
              _buildIconButton(
                icon: Icons.add,
                color: TZColors.primaryPurple,
                bgColor: const Color(0xFFF5F3FF),
                onTap: () => _showNewChatDialog(),
              ),
            ],
          ),
          // 搜索栏
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showSearch
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildSearchBar(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// IM 连接状态指示器
  Widget _buildConnectionIndicator(IMConnectionStatus status) {
    Color color;
    String text;
    switch (status) {
      case IMConnectionStatus.loggedIn:
        color = const Color(0xFF10B981);
        text = '已连接';
        break;
      case IMConnectionStatus.connecting:
        color = const Color(0xFFF59E0B);
        text = '连接中...';
        break;
      case IMConnectionStatus.connected:
        color = const Color(0xFF10B981);
        text = '已连接';
        break;
      case IMConnectionStatus.kicked:
        color = const Color(0xFFEF4444);
        text = '被踢出';
        break;
      case IMConnectionStatus.tokenExpired:
        color = const Color(0xFFEF4444);
        text = 'Token过期';
        break;
      case IMConnectionStatus.disconnected:
        color = const Color(0xFF9CA3AF);
        text = '演示模式';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 2),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        autofocus: true,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: const InputDecoration(
          hintText: '搜索聊天、群组、功能...',
          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Color(0xFF9CA3AF), size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildChatListContent() {
    final imService = context.watch<IMService>();
    final convService = context.watch<TZConversationService>();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 筛选标签
        _buildFilterTabs(),
        const SizedBox(height: 8),

        // 根据 IM 登录状态决定数据来源
        if (imService.isLoggedIn) ...[
          // ═══ 真实 IM 会话列表 ═══
          if (convService.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredIMConversations.isEmpty)
            _buildEmptyList()
          else
            ..._filteredIMConversations.map((conv) {
              final isDesktop = Responsive.isDesktop(context);
              final isSelected = isDesktop && _selectedConversationId == conv.conversationId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildIMConversationCard(conv, isSelected),
              );
            }),
        ] else ...[
          // ═══ Mock 数据（演示模式） ═══
          if (_filteredMockChats.isEmpty)
            _buildEmptyList()
          else
            ..._filteredMockChats.map((chat) {
              final isDesktop = Responsive.isDesktop(context);
              final isSelected = isDesktop && _selectedChatId == chat.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChatItemCard(
                  chat: chat,
                  isSelected: isSelected,
                  onTap: () => _onMockChatTap(chat),
                ),
              );
            }),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  /// 真实 IM 会话卡片
  Widget _buildIMConversationCard(TZConversation conv, bool isSelected) {
    final isP2P = conv.type == NIMConversationType.p2p;

    return GestureDetector(
      onTap: () => _onIMConversationTap(conv),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF5F3FF)
              : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFDDD6FE) : const Color(0xFFF3F4F6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isP2P
                    ? const Color(0xFFDBEAFE)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: conv.avatar.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          conv.avatar,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            isP2P ? Icons.person : Icons.group,
                            color: isP2P
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF10B981),
                            size: 24,
                          ),
                        ),
                      )
                    : Icon(
                        isP2P ? Icons.person : Icons.group,
                        color: isP2P
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF10B981),
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.name.isNotEmpty ? conv.name : conv.targetId,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.lastMessageTime != null)
                        Text(
                          _formatTime(conv.lastMessageTime!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.lastMessage.isNotEmpty ? conv.lastMessage : '暂无消息',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 18),
                          decoration: BoxDecoration(
                            color: conv.isMuted
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chatFilters.map((f) {
          final isActive = _activeFilter == f.key;
          final count = f.type != null ? _getFilterCount(f) : null;
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = f.key),
              child: Container(
                padding: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? f.color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isActive ? f.color : const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? f.color.withOpacity(0.7)
                              : const Color(0xFF9CA3AF).withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyList() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          const Text(
            '暂无聊天记录',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
