/// 途正英语 - 主框架页面
/// 火鹰科技出品
///
/// 移动端：底部 Tab 导航（消息/学习/商城/直播/我的）
/// 桌面端：左侧竖向图标导航栏（微信桌面版风格）
///
/// 对标原型：MobileTabBar + DesktopSideNav
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';
import '../services/conversation_service.dart';
import 'home_page.dart';
import 'chat/chat_list_page.dart';

// ═══════════════════════════════════════════════════════
// 占位页面
// ═══════════════════════════════════════════════════════

class _PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _PlaceholderPage({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.5, -1),
          end: Alignment(0.5, 1),
          colors: [TZColors.bgStart, TZColors.bgPurple, TZColors.bgMid, TZColors.bgEnd],
          stops: [0.0, 0.15, 0.4, 1.0],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: TZColors.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              '功能开发中，敬请期待...',
              style: TextStyle(fontSize: 14, color: TZColors.textGray),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 主框架
// ═══════════════════════════════════════════════════════

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  // Tab 页面
  final List<Widget> _pages = [
    const ChatListPage(),
    const HomePage(),
    const _PlaceholderPage(title: '课程商城', icon: Icons.shopping_bag_outlined, color: TZColors.primaryPurple),
    const _PlaceholderPage(title: '直播课堂', icon: Icons.videocam_outlined, color: Color(0xFFEF4444)),
    const _PlaceholderPage(title: '我的', icon: Icons.person_outline, color: TZColors.blue),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  // ═══ 桌面端：左侧图标导航栏 ═══
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左侧竖向导航栏
          _buildDesktopSideNav(),
          // 主内容区
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSideNav() {
    // 监听真实未读数
    final unreadCount = context.watch<TZConversationService>().totalUnreadCount;

    return Container(
      width: 64,
      decoration: const BoxDecoration(
        color: Color(0xFFF0EDFF),
        border: Border(right: BorderSide(color: Color(0xFFE9E5FF))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // 用户头像
          GestureDetector(
            onTap: () => setState(() => _currentIndex = 4),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Text('张', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 首页按钮
          _buildSideNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: '首页',
            index: 1,
          ),
          const SizedBox(height: 4),
          // 功能导航（消息使用真实未读数）
          _buildSideNavItem(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble,
            label: '消息',
            index: 0,
            badge: unreadCount,
          ),
          const SizedBox(height: 4),
          ..._sideNavItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildSideNavItem(
                icon: item.icon,
                activeIcon: item.activeIcon,
                label: item.label,
                index: item.tabIndex,
                badge: item.badge,
              ),
            );
          }),
          const Spacer(),
          // 设置
          _buildSideNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: '设置',
            index: 4,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSideNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    int badge = 0,
  }) {
    final isActive = _currentIndex == index;
    return Tooltip(
      message: label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? TZColors.primaryPurple : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    isActive ? activeIcon : icon,
                    size: 20,
                    color: isActive ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ 移动端：底部 Tab 导航栏 ═══
  Widget _buildMobileLayout() {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    // 监听真实未读数
    final unreadCount = context.watch<TZConversationService>().totalUnreadCount;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _tabItems.asMap().entries.map((entry) {
              final i = entry.key;
              final tab = entry.value;
              final isActive = _currentIndex == i;
              // 消息 Tab 使用真实未读数
              final badge = i == 0 ? unreadCount : tab.badge;
              return GestureDetector(
                onTap: () => setState(() => _currentIndex = i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 活跃指示器
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isActive ? 20 : 0,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: TZColors.primaryPurple,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      // 图标 + 红点
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            isActive ? tab.activeIcon : tab.icon,
                            size: 22,
                            color: isActive ? TZColors.primaryPurple : const Color(0xFF9CA3AF),
                          ),
                          if (badge > 0)
                            Positioned(
                              top: -4,
                              right: -8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                constraints: const BoxConstraints(minWidth: 16),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  borderRadius: BorderRadius.all(Radius.circular(8)),
                                ),
                                child: Center(
                                  child: Text(
                                    badge > 99 ? '99+' : '$badge',
                                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // 标签
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? TZColors.primaryPurple : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Tab 配置数据
// ═══════════════════════════════════════════════════════

class _TabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badge;
  const _TabItem({required this.label, required this.icon, required this.activeIcon, this.badge = 0});
}

const List<_TabItem> _tabItems = [
  _TabItem(label: '消息', icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble),
  _TabItem(label: '学习', icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book),
  _TabItem(label: '商城', icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag),
  _TabItem(label: '直播', icon: Icons.videocam_outlined, activeIcon: Icons.videocam),
  _TabItem(label: '我的', icon: Icons.person_outline, activeIcon: Icons.person),
];

class _SideNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int tabIndex;
  final int badge;
  const _SideNavItem({required this.icon, required this.activeIcon, required this.label, required this.tabIndex, this.badge = 0});
}

const List<_SideNavItem> _sideNavItems = [
  _SideNavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: '学习', tabIndex: 2),
  _SideNavItem(icon: Icons.assignment_outlined, activeIcon: Icons.assignment, label: '作业', tabIndex: 2),
  _SideNavItem(icon: Icons.videocam_outlined, activeIcon: Icons.videocam, label: '直播', tabIndex: 3),
  _SideNavItem(icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag, label: '商城', tabIndex: 2),
  _SideNavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: '课表', tabIndex: 2),
  _SideNavItem(icon: Icons.school_outlined, activeIcon: Icons.school, label: '单词', tabIndex: 2),
  _SideNavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: '发现', tabIndex: 2),
];
