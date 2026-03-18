/// 途正英语 - 聊天列表页面（对标HelloTalk）
/// 火鹰科技出品
///
/// 移动端：单列聊天列表，点击跳转到 ChatRoom 页面
/// 桌面端：微信桌面版左右分栏布局（左侧聊天列表 + 右侧聊天内容）
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';
import '../../utils/responsive.dart';
import 'chat_panel.dart';
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
  String? _selectedChatId = 'yangma-digital';
  final TextEditingController _searchController = TextEditingController();

  List<ChatItem> get _filteredChats {
    return mockChatList.where((c) {
      // 筛选类型
      if (_activeFilter != 'all') {
        final filterType = chatFilters.firstWhere((f) => f.key == _activeFilter).type;
        if (filterType != null && c.type != filterType) return false;
      }
      // 搜索
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

  void _onChatTap(ChatItem chat) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      setState(() {
        _selectedChatId = chat.id;
      });
    } else {
      // 移动端跳转到聊天室
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomPage(chatId: chat.id),
        ),
      );
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
              // 顶部标题栏
              _buildListHeader(),
              // 可滚动内容
              Expanded(
                child: _buildChatListContent(),
              ),
            ],
          ),
        ),
        // 右侧内容面板
        Expanded(
          child: _selectedChatId != null
              ? ChatPanel(
                  key: ValueKey(_selectedChatId),
                  chatId: _selectedChatId!,
                )
              : _buildEmptyPanel(),
        ),
      ],
    );
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
                onTap: () {},
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
    final chats = _filteredChats;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 筛选标签
        _buildFilterTabs(),
        const SizedBox(height: 8),
        // 聊天列表
        if (chats.isEmpty)
          _buildEmptyList()
        else
          ...chats.map((chat) {
            final isDesktop = Responsive.isDesktop(context);
            final isSelected = isDesktop && _selectedChatId == chat.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChatItemCard(
                chat: chat,
                isSelected: isSelected,
                onTap: () => _onChatTap(chat),
              ),
            );
          }),
        const SizedBox(height: 80),
      ],
    );
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
