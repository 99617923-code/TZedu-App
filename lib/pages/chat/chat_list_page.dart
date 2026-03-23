/// 途正英语 - 聊天列表页面（对标HelloTalk）
/// 火鹰科技出品
///
/// 移动端：单列聊天列表，点击跳转到 ChatRoom 页面
/// 桌面端：微信桌面版左右分栏布局（左侧聊天列表 + 右侧聊天内容）
///
/// 数据来源：
/// - 已登录 IM（移动端）：从 NIM SDK ConversationService 获取真实会话数据
/// - 已登录 IM（桌面端）：从本地缓存获取会话数据（NIM PC SDK ConversationService 不可用）
/// - 未登录 IM：显示 Mock 数据（开发/演示模式）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nim_core_v2/nim_core.dart';
import '../../config/theme.dart';
import '../../models/chat_data.dart';
import '../../utils/responsive.dart';
import '../../services/im_service.dart';
import '../../services/auth_service.dart';
import '../../services/conversation_service.dart';
import 'chat_panel.dart';
import 'chat_panel_im.dart';
import 'chat_room_page.dart';
import 'widgets/chat_item_card.dart';
import 'select_contacts_page.dart';
import 'create_team_page.dart';
import '../../services/team_service.dart';

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
  /// 业务已登录即显示 IM 会话列表（避免 IM 异步登录时闪现 Mock 数据）
  bool get _useRealIM => context.read<AuthService>().isLoggedIn;

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

  /// 显示发起新聊天对话框（通过手机号搜索用户）
  void _showNewChatDialog() {
    final authService = context.read<AuthService>();
    if (!authService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先登录'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    // 显示选择弹窗：发起私聊 / 发起群聊
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
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_add_alt_1, color: Color(0xFF7C3AED), size: 20),
                ),
                title: const Text('发起私聊', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('通过手机号搜索用户', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                onTap: () {
                  Navigator.pop(ctx);
                  _showP2PChatDialog();
                },
              ),
              const Divider(height: 1, indent: 68),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group_add, color: Color(0xFF10B981), size: 20),
                ),
                title: const Text('发起群聊', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('选择联系人创建群聊', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateTeamFlow();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示发起私聊对话框
  void _showP2PChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _NewChatDialog(
        onStartChat: (accid, nickname) => _startP2PChat(accid, nickname),
      ),
    );
  }

  /// 发起群聊流程：选择联系人 -> 填写群信息 -> 创建
  Future<void> _showCreateTeamFlow() async {
    final isDesktop = Responsive.isDesktop(context);

    // 第一步：选择联系人
    final selectedContacts = await Navigator.of(context).push<List<SelectableContact>>(
      MaterialPageRoute(
        builder: (_) => const SelectContactsPage(
          title: '选择群聊成员',
        ),
      ),
    );

    if (selectedContacts == null || selectedContacts.isEmpty || !mounted) return;

    // 第二步：填写群信息并创建
    if (isDesktop) {
      // 桌面端：直接创建群聊（使用默认群名）
      final names = selectedContacts.map((c) => c.name).toList();
      final defaultName = names.length <= 3
          ? names.join('、')
          : '${names.take(3).join('、')}等${names.length}人';

      final accids = selectedContacts.map((c) => c.accid).toList();
      final result = await TZTeamService.instance.createTeam(
        name: defaultName,
        inviteeAccids: accids,
      );

      if (!mounted) return;

      if (result.success && result.conversationId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('群聊创建成功'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() {
          _selectedConversationId = result.conversationId;
          _selectedChatId = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建失败: ${result.error ?? "未知错误"}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } else {
      // 移动端：跳转到创建群聊页面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreateTeamPage(selectedContacts: selectedContacts),
        ),
      );
    }
  }

  /// 通过 accid 发起 P2P 聊天
  Future<void> _startP2PChat(String targetAccid, String displayName) async {
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

      // 在本地会话列表中添加/更新此会话（桌面端和移动端都适用）
      await TZConversationService.instance.addOrUpdateLocalConversation(
        conversationId: conversationId,
        type: NIMConversationType.p2p,
        targetId: targetAccid,
        name: displayName,
      );

      if (!mounted) return;

      final isDesktop = Responsive.isDesktop(context);

      if (isDesktop) {
        setState(() {
          _selectedConversationId = conversationId;
          _selectedChatId = null;
        });
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomPage(
              conversationId: conversationId,
              conversationName: displayName,
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
    final imService = context.watch<IMService>();
    final isIMConnected = imService.isLoggedIn;

    return Container(
      color: const Color(0xFFFAFAFA),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIMConnected ? Icons.chat_bubble_outline : Icons.cloud_off,
              size: 64,
              color: const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 16),
            Text(
              isIMConnected ? '选择一个聊天开始对话' : '选择一个聊天开始对话',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
            if (isIMConnected) ...[
              const SizedBox(height: 8),
              Text(
                '点击 + 按钮搜索手机号发起新聊天',
                style: TextStyle(
                  fontSize: 12,
                  color: const Color(0xFF9CA3AF).withOpacity(0.7),
                ),
              ),
            ],
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
              _buildConnectionIndicator(imService),
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

  /// IM 连接状态指示器（改进版：区分桌面模式和演示模式）
  Widget _buildConnectionIndicator(IMService imService) {
    Color color;
    String text;
    IconData? icon;

    final status = imService.connectionStatus;

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
        icon = Icons.warning_amber;
        break;
      case IMConnectionStatus.tokenExpired:
        color = const Color(0xFFEF4444);
        text = 'Token过期';
        icon = Icons.warning_amber;
        break;
      case IMConnectionStatus.disconnected:
        // 区分：业务已登录但 IM 未连接 vs 完全未登录
        final authService = context.read<AuthService>();
        if (authService.isLoggedIn) {
          color = const Color(0xFFF59E0B);
          text = '未连接';
          icon = Icons.cloud_off;
        } else {
          color = const Color(0xFF9CA3AF);
          text = '演示模式';
        }
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
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
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
    final authService = context.watch<AuthService>();
    final imService = context.watch<IMService>();
    final convService = context.watch<TZConversationService>();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 筛选标签
        _buildFilterTabs(),
        const SizedBox(height: 8),

        // 根据业务登录状态决定数据来源（避免 IM 异步登录时闪现 Mock 数据）
        if (authService.isLoggedIn) ...[
          // ═══ 真实 IM 会话列表（移动端从 SDK，桌面端从本地缓存） ═══
          if (convService.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredIMConversations.isEmpty)
            _buildEmptyIMList()
          else
            ..._filteredIMConversations.map((conv) {
              final isDesktop = Responsive.isDesktop(context);
              final isSelected = isDesktop && _selectedConversationId == conv.conversationId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildIMConversationCard(conv, isSelected),
              );
            }),
        ] else if (!authService.isLoggedIn) ...[
          // ═══ Mock 数据（未登录时的演示模式） ═══
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
      onLongPress: () => _showConversationActions(conv),
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
                          errorBuilder: (_, __, ___) => _buildConversationAvatarFallback(conv, isP2P),
                        ),
                      )
                    : _buildConversationAvatarFallback(conv, isP2P),
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

  /// 会话头像回退显示（名称首字母或图标）
  Widget _buildConversationAvatarFallback(TZConversation conv, bool isP2P) {
    final displayName = conv.name.isNotEmpty ? conv.name : conv.targetId;
    if (displayName.isNotEmpty) {
      return Text(
        displayName[0].toUpperCase(),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isP2P ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
        ),
      );
    }
    return Icon(
      isP2P ? Icons.person : Icons.group,
      color: isP2P ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
      size: 24,
    );
  }

  /// 长按会话显示操作菜单
  void _showConversationActions(TZConversation conv) {
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
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  conv.name.isNotEmpty ? conv.name : conv.targetId,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Divider(),
              // 置顶/取消置顶
              ListTile(
                leading: Icon(
                  conv.isStickTop ? Icons.push_pin_outlined : Icons.push_pin,
                  color: const Color(0xFF7C3AED),
                ),
                title: Text(conv.isStickTop ? '取消置顶' : '置顶'),
                onTap: () {
                  Navigator.pop(ctx);
                  TZConversationService.instance.toggleStickTop(conv.conversationId);
                },
              ),
              // 标记已读
              if (conv.unreadCount > 0)
                ListTile(
                  leading: const Icon(Icons.done_all, color: Color(0xFF10B981)),
                  title: const Text('标记已读'),
                  onTap: () {
                    Navigator.pop(ctx);
                    TZConversationService.instance.markConversationRead(conv.conversationId);
                  },
                ),
              // 免打扰
              ListTile(
                leading: Icon(
                  conv.isMuted ? Icons.notifications_active : Icons.notifications_off_outlined,
                  color: const Color(0xFFF59E0B),
                ),
                title: Text(conv.isMuted ? '取消免打扰' : '消息免打扰'),
                onTap: () {
                  Navigator.pop(ctx);
                  TZConversationService.instance.toggleMute(conv.conversationId);
                },
              ),
              // 删除会话
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: const Text('删除会话', style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteConversation(conv);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 确认删除会话
  void _confirmDeleteConversation(TZConversation conv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除会话'),
        content: Text('确定要删除与 "${conv.name.isNotEmpty ? conv.name : conv.targetId}" 的会话吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              TZConversationService.instance.deleteConversation(conv.conversationId);
              if (_selectedConversationId == conv.conversationId) {
                setState(() => _selectedConversationId = null);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
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

  /// IM 已登录但会话列表为空时的提示
  Widget _buildEmptyIMList() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          const Text(
            '暂无聊天记录',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击右上角 + 搜索手机号发起新聊天',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFD1D5DB),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _showNewChatDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1, size: 16, color: Color(0xFF7C3AED)),
                  SizedBox(width: 6),
                  Text(
                    '发起新聊天',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyList() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFFD1D5DB)),
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

// ═══════════════════════════════════════════════════════════════
// 发起新聊天对话框（手机号搜索用户）
// ═══════════════════════════════════════════════════════════════

class _NewChatDialog extends StatefulWidget {
  final void Function(String accid, String nickname) onStartChat;

  const _NewChatDialog({required this.onStartChat});

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _phoneController = TextEditingController();
  bool _isSearching = false;
  SearchedUser? _foundUser;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = '请输入手机号');
      return;
    }

    // 简单的手机号格式验证
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _errorMessage = '请输入正确的11位手机号');
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _foundUser = null;
    });

    try {
      final result = await AuthService.instance.searchUserByPhone(phone);

      if (!mounted) return;

      if (result.success && result.user != null) {
        setState(() {
          _foundUser = result.user;
          _isSearching = false;
        });
      } else {
        setState(() {
          _errorMessage = result.message ?? '未找到该用户';
          _isSearching = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '搜索失败: $e';
        _isSearching = false;
      });
    }
  }

  void _confirmStartChat() {
    if (_foundUser == null || _foundUser!.accid.isEmpty) {
      setState(() => _errorMessage = '该用户暂无 IM 账号，无法发起聊天');
      return;
    }

    Navigator.of(context).pop();
    widget.onStartChat(_foundUser!.accid, _foundUser!.nickname);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.person_add_alt_1, color: Color(0xFF7C3AED), size: 24),
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
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入对方手机号搜索用户，找到后即可发起私聊',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),

            // 手机号输入 + 搜索按钮
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    decoration: InputDecoration(
                      hintText: '请输入手机号',
                      hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
                      prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF7C3AED)),
                      counterText: '',
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
                    onSubmitted: (_) => _searchUser(),
                    onChanged: (_) {
                      // 清除之前的搜索结果
                      if (_foundUser != null || _errorMessage != null) {
                        setState(() {
                          _foundUser = null;
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _searchUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('搜索', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),

            // 错误提示
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 搜索结果 - 用户卡片
            if (_foundUser != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Row(
                  children: [
                    // 头像
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _foundUser!.avatar.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                _foundUser!.avatar,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                    _foundUser!.nickname.isNotEmpty
                                        ? _foundUser!.nickname[0]
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF3B82F6),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                _foundUser!.nickname.isNotEmpty
                                    ? _foundUser!.nickname[0]
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // 用户信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _foundUser!.nickname.isNotEmpty
                                      ? _foundUser!.nickname
                                      : '未设置昵称',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDDD6FE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _foundUser!.roleLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _foundUser!.phone.isNotEmpty
                                ? '${_foundUser!.phone.substring(0, 3)}****${_foundUser!.phone.substring(7)}'
                                : '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 发起聊天按钮
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
        if (_foundUser != null)
          ElevatedButton.icon(
            onPressed: _confirmStartChat,
            icon: const Icon(Icons.chat, size: 16),
            label: const Text('发起聊天', style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
      ],
    );
  }
}
