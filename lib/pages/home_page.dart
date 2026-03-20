/// 途正英语 - 首页
/// 火鹰科技出品
///
/// 设计还原自 TZ-IELTS 原型：
/// 混合布局 - 核心功能大图卡片 + 快捷入口紧凑列表
/// 手机端：大卡片竖排 + 快捷入口1列
/// 平板端：大卡片横向并排 + 快捷入口2列
/// 桌面端：大卡片3列 + 快捷入口3列
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/app_role.dart';
import '../models/home_data.dart';
import '../widgets/feature_card.dart';
import '../widgets/quick_entry.dart';
import '../widgets/role_switcher.dart';
import '../widgets/hero_banner.dart';
import '../services/update_service.dart';
import '../utils/responsive.dart';
import 'test/test_page.dart';
import 'test/test_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  AppRole _currentRole = AppRole.student;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _fadeController.forward();

    // 启动时检查更新
    _checkUpdate();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final updateInfo = await UpdateService().checkForUpdate();
    if (updateInfo.hasUpdate && mounted) {
      UpdateService.showUpdateDialog(context, updateInfo);
    }
  }

  void _switchRole(AppRole role) {
    if (role == _currentRole) return;
    _fadeController.reverse().then((_) {
      setState(() => _currentRole = role);
      _fadeController.forward();
    });
  }

  void _showFeatureComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「$title」功能开发中，敬请期待...'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: TZColors.deepPurple,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showUpdateCheck() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: TZColors.primaryPurple),
                SizedBox(height: 16),
                Text('正在检查更新...', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    final updateInfo = await UpdateService().checkForUpdate();
    if (!mounted) return;
    Navigator.of(context).pop();

    if (updateInfo.hasUpdate) {
      UpdateService.showUpdateDialog(context, updateInfo);
    } else {
      UpdateService.showUpToDateSnackBar(context, updateInfo.currentVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final featureCols = Responsive.featureCardColumns(context);
    final entryCols = Responsive.quickEntryColumns(context);
    final features = HomeDataProvider.getFeatures(_currentRole);
    final quickEntries = HomeDataProvider.getQuickEntries(_currentRole);

    return Scaffold(
      body: Container(
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
        child: Stack(
          children: [
            // 背景装饰圆
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TZColors.primaryPurple.withOpacity(0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TZColors.red.withOpacity(0.04),
                ),
              ),
            ),

            // 主内容
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth),
                    child: CustomScrollView(
                      slivers: [
                      // ═══ Header ═══
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 20, padding, 8),
                          child: Row(
                            children: [
                              // 用户头像 + 信息
                              GestureDetector(
                                onTap: () => _showFeatureComingSoon('个人中心'),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: _currentRole.gradient,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF3B3486).withOpacity(0.2),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          _currentRole.userName[0],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _currentRole.displayName,
                                          style: const TextStyle(
                                            color: TZColors.textDark,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _currentRole.endLabel,
                                          style: const TextStyle(
                                            color: TZColors.textGray,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // 角色切换
                              RoleSwitcher(
                                currentRole: _currentRole,
                                onRoleChanged: _switchRole,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ═══ Hero Banner ═══
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 12, padding, 20),
                          child: HeroBanner(role: _currentRole),
                        ),
                      ),

                      // ═══ 核心功能大图卡片 ═══
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: _buildFeatureGrid(features, featureCols),
                          ),
                        ),
                      ),

                      // ═══ 快捷入口标题 ═══
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(padding + 4, 24, padding, 12),
                            child: const Row(
                              children: [
                                Icon(Icons.auto_awesome, color: TZColors.primaryPurple, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  '快捷入口',
                                  style: TextStyle(
                                    color: TZColors.textMedium,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ═══ 快捷入口网格 ═══
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            child: _buildQuickEntryGrid(quickEntries, entryCols),
                          ),
                        ),
                      ),

                      // ═══ 后台入口 + 检查更新 ═══
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(padding, 24, padding, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_currentRole == AppRole.teacher)
                                _buildBottomButton(
                                  icon: Icons.dashboard_outlined,
                                  label: '老师后台',
                                  color: TZColors.primaryPurple,
                                  bgColor: const Color(0xFFF5F3FF),
                                  borderColor: const Color(0xFFEDE9FE),
                                  onTap: () => _showFeatureComingSoon('老师后台'),
                                ),
                              if (_currentRole == AppRole.teacher) const SizedBox(width: 12),
                              _buildBottomButton(
                                icon: Icons.settings_outlined,
                                label: '管理后台',
                                color: TZColors.textGray,
                                bgColor: const Color(0xFFF9FAFB),
                                borderColor: const Color(0xFFF3F4F6),
                                onTap: () => _showFeatureComingSoon('管理后台'),
                              ),
                              const SizedBox(width: 12),
                              _buildBottomButton(
                                icon: Icons.psychology_outlined,
                                label: 'AI 测评',
                                color: const Color(0xFF7C3AED),
                                bgColor: const Color(0xFFF5F3FF),
                                borderColor: const Color(0xFFEDE9FE),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const TestPage()),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              _buildBottomButton(
                                icon: Icons.system_update_outlined,
                                label: '检查更新',
                                color: TZColors.green,
                                bgColor: const Color(0xFFF0FDF4),
                                borderColor: const Color(0xFFDCFCE7),
                                onTap: _showUpdateCheck,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ═══ Footer ═══
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 24),
                          child: Center(
                            child: Text(
                              AppConstants.copyright,
                              style: const TextStyle(
                                color: TZColors.textLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid(List<FeatureCardData> features, int columns) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final availableWidth = constraints.maxWidth - (spacing * (columns - 1));
        final itemWidth = availableWidth / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: features.map((f) {
            // 第一张大卡片在手机端占满宽度
            final width = (f.isLarge && columns == 2)
                ? constraints.maxWidth
                : itemWidth;
            return SizedBox(
              width: width,
              child: FeatureCard(
                data: f,
                onTap: () => _showFeatureComingSoon(f.title),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildQuickEntryGrid(List<QuickEntryData> entries, int columns) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.0;
        final availableWidth = constraints.maxWidth - (spacing * (columns - 1));
        final itemWidth = availableWidth / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: entries.map((e) {
            return SizedBox(
              width: columns == 1 ? constraints.maxWidth : itemWidth,
              child: QuickEntry(
                data: e,
                onTap: () => _showFeatureComingSoon(e.label),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
