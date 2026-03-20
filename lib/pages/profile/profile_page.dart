/// 途正英语 - 我的页面
/// 火鹰科技出品
///
/// 展示用户信息、角色标签、功能入口、登录/登出
/// 用户体系完全自建，零依赖第三方平台
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../services/auth_service.dart';
import '../../services/im_service.dart';

class ProfilePage extends StatelessWidget {
  final VoidCallback? onLogout;
  final VoidCallback? onLoginTap;
  const ProfilePage({super.key, this.onLogout, this.onLoginTap});

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
      child: SafeArea(
        child: Consumer<AuthService>(
          builder: (context, auth, _) {
            if (!auth.isLoggedIn) {
              return _buildNotLoggedIn(context);
            }
            return _buildLoggedIn(context, auth);
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 未登录状态
  // ═══════════════════════════════════════════════════════

  Widget _buildNotLoggedIn(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
            ),
            child: const Icon(Icons.person_outline, size: 40, color: TZColors.textGray),
          ),
          const SizedBox(height: 16),
          const Text(
            '未登录',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TZColors.textDark),
          ),
          const SizedBox(height: 8),
          const Text(
            '登录后即可使用全部功能',
            style: TextStyle(fontSize: 14, color: TZColors.textGray),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            height: 48,
            child: ElevatedButton(
              onPressed: onLoginTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: TZColors.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('立即登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 已登录状态
  // ═══════════════════════════════════════════════════════

  Widget _buildLoggedIn(BuildContext context, AuthService auth) {
    final user = auth.currentUser!;
    final isDesktop = Responsive.isDesktop(context);
    final padding = Responsive.horizontalPadding(context);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
        child: Column(
          children: [
            // 页面标题
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '我的',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: TZColors.textDark),
                ),
              ),
            ),
            // 用户信息卡片
            _buildUserCard(context, user),
            const SizedBox(height: 16),
            // IM 连接状态
            _buildIMStatusCard(context),
            const SizedBox(height: 16),
            // 功能菜单
            _buildMenuSection(context),
            const SizedBox(height: 16),
            // 关于
            _buildAboutSection(context),
            const SizedBox(height: 24),
            // 退出登录
            _buildLogoutButton(context, auth),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, UserProfile user) {
    final roleLabel = _getRoleLabel(user.role);
    final roleColors = _getRoleColors(user.role);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: roleColors,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: roleColors[0].withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                user.nickname.isNotEmpty ? user.nickname[0] : '?',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 用户信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.nickname,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TZColors.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: roleColors),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        roleLabel,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (user.phone != null && user.phone!.isNotEmpty)
                  Text(
                    _maskPhone(user.phone!),
                    style: const TextStyle(fontSize: 13, color: TZColors.textGray),
                  ),
                Text(
                  'ID: ${user.userId}',
                  style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.6)),
                ),
              ],
            ),
          ),
          // 编辑按钮
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('编辑资料功能即将开放'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.edit_outlined, color: TZColors.primaryPurple, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildIMStatusCard(BuildContext context) {
    return Consumer<IMService>(
      builder: (context, im, _) {
        final isConnected = im.isLoggedIn;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isConnected ? TZColors.green : TZColors.errorRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'IM 消息服务',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TZColors.textDark),
              ),
              const Spacer(),
              Text(
                isConnected ? '已连接' : '未连接',
                style: TextStyle(
                  fontSize: 13,
                  color: isConnected ? TZColors.green : TZColors.errorRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final menuItems = [
      _MenuItem(icon: Icons.notifications_outlined, title: '消息通知', subtitle: '管理推送和免打扰'),
      _MenuItem(icon: Icons.security_outlined, title: '账号安全', subtitle: '密码、绑定手机'),
      _MenuItem(icon: Icons.storage_outlined, title: '存储管理', subtitle: '清理缓存数据'),
      _MenuItem(icon: Icons.help_outline, title: '帮助与反馈', subtitle: '常见问题、意见反馈'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: menuItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: TZColors.primaryPurple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, size: 18, color: TZColors.primaryPurple),
                ),
                title: Text(item.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TZColors.textDark)),
                subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 12, color: TZColors.textGray)),
                trailing: const Icon(Icons.chevron_right, color: TZColors.textLight, size: 20),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${item.title}功能即将开放'), duration: const Duration(seconds: 2)),
                  );
                },
              ),
              if (i < menuItems.length - 1)
                Divider(height: 1, indent: 68, endIndent: 16, color: Colors.grey.withOpacity(0.1)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TZColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.info_outline, size: 18, color: TZColors.blue),
            ),
            title: const Text('关于途正英语', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TZColors.textDark)),
            subtitle: const Text('v1.0.0 · 火鹰科技出品', style: TextStyle(fontSize: 12, color: TZColors.textGray)),
            trailing: const Icon(Icons.chevron_right, color: TZColors.textLight, size: 20),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: '途正英语',
                applicationVersion: 'v1.0.0',
                applicationLegalese: '广州火鹰信息科技有限公司\nwww.figo.cn',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, AuthService auth) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('确认退出'),
              content: const Text('退出后将无法接收消息，确定要退出登录吗？'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消', style: TextStyle(color: TZColors.textGray)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('退出', style: TextStyle(color: TZColors.errorRed)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await auth.logout();
            onLogout?.call();
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: TZColors.errorRed,
          side: const BorderSide(color: TZColors.errorRed, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('退出登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════

  String _getRoleLabel(String role) {
    switch (role) {
      case 'teacher':
        return '教师';
      case 'parent':
        return '家长';
      case 'admin':
        return '管理员';
      default:
        return '学生';
    }
  }

  List<Color> _getRoleColors(String role) {
    switch (role) {
      case 'teacher':
        return TZColors.teacherGradient;
      case 'parent':
        return TZColors.parentGradient;
      case 'admin':
        return [TZColors.blue, TZColors.deepBlue];
      default:
        return TZColors.studentGradient;
    }
  }

  String _maskPhone(String phone) {
    if (phone.length >= 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  const _MenuItem({required this.icon, required this.title, required this.subtitle});
}
