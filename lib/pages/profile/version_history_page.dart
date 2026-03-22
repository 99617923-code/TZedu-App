/// 途正英语 - 版本管理页面
/// 火鹰科技出品
///
/// 仅管理员可见，展示完整的版本更新历史
/// 支持按版本类型筛选、版本详情展开、数据同步到后端

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/app_version.dart';
import '../../services/version_service.dart';
import '../../services/auth_service.dart';

class VersionHistoryPage extends StatefulWidget {
  const VersionHistoryPage({super.key});

  @override
  State<VersionHistoryPage> createState() => _VersionHistoryPageState();
}

class _VersionHistoryPageState extends State<VersionHistoryPage> {
  final VersionService _versionService = VersionService();
  String _selectedFilter = 'all'; // all / major / minor / patch / hotfix
  String? _expandedVersion; // 当前展开的版本号
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final auth = context.read<AuthService>();
    await _versionService.initialize(authToken: auth.bizToken);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        title: const Text('版本管理', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: TZColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          // 同步到后端按钮
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TZColors.primaryPurple),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            tooltip: '同步到后端',
            onPressed: _isSyncing ? null : _syncToBackend,
          ),
          // 导出 JSON 按钮
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出 JSON',
            onPressed: _exportJson,
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计概览卡片
          _buildStatisticsCard(),
          // 筛选标签
          _buildFilterTabs(),
          // 版本列表
          Expanded(child: _buildVersionList()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 统计概览
  // ═══════════════════════════════════════════════════════

  Widget _buildStatisticsCard() {
    final stats = _versionService.getStatistics();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('版本统计', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_versionService.lastSyncTime != null)
                Text(
                  '上次同步: ${_formatTime(_versionService.lastSyncTime!)}',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem('版本数', '${stats['total_versions'] ?? 0}', Icons.tag),
              _buildStatItem('新功能', '${stats['total_features'] ?? 0}', Icons.auto_awesome),
              _buildStatItem('修复', '${stats['total_fixes'] ?? 0}', Icons.build_circle),
              _buildStatItem('优化', '${stats['total_improvements'] ?? 0}', Icons.trending_up),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 筛选标签
  // ═══════════════════════════════════════════════════════

  Widget _buildFilterTabs() {
    final filters = [
      {'key': 'all', 'label': '全部'},
      {'key': 'major', 'label': '重大更新'},
      {'key': 'minor', 'label': '功能更新'},
      {'key': 'patch', 'label': '问题修复'},
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter['label']!),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedFilter = filter['key']!);
              },
              selectedColor: TZColors.primaryPurple.withOpacity(0.15),
              checkmarkColor: TZColors.primaryPurple,
              labelStyle: TextStyle(
                color: isSelected ? TZColors.primaryPurple : TZColors.textGray,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? TZColors.primaryPurple.withOpacity(0.3) : Colors.grey.withOpacity(0.15),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 版本列表
  // ═══════════════════════════════════════════════════════

  Widget _buildVersionList() {
    final allVersions = _versionService.getAllVersions();
    final filteredVersions = _selectedFilter == 'all'
        ? allVersions
        : allVersions.where((v) => v.type == _selectedFilter).toList();

    if (filteredVersions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('暂无版本记录', style: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVersions,
      color: TZColors.primaryPurple,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: filteredVersions.length,
        itemBuilder: (context, index) {
          final version = filteredVersions[index];
          final isExpanded = _expandedVersion == version.version;
          final isLatest = index == 0 && _selectedFilter == 'all';
          return _buildVersionCard(version, isExpanded, isLatest);
        },
      ),
    );
  }

  Widget _buildVersionCard(AppVersion version, bool isExpanded, bool isLatest) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isLatest
            ? Border.all(color: TZColors.primaryPurple.withOpacity(0.3), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 版本头部（始终显示）
          InkWell(
            onTap: () {
              setState(() {
                _expandedVersion = isExpanded ? null : version.version;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：版本号 + 类型标签 + 日期
                  Row(
                    children: [
                      // 版本号
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getTypeColor(version.type).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'v${version.version}',
                          style: TextStyle(
                            color: _getTypeColor(version.type),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 类型标签
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getTypeColor(version.type).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _getTypeColor(version.type).withOpacity(0.2)),
                        ),
                        child: Text(
                          version.typeLabel,
                          style: TextStyle(
                            color: _getTypeColor(version.type),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isLatest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '最新',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      const Spacer(),
                      // 日期
                      Text(
                        version.releaseDate,
                        style: const TextStyle(color: TZColors.textGray, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: TZColors.textGray,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 版本标题
                  Text(
                    version.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: TZColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 版本描述
                  Text(
                    version.description,
                    style: const TextStyle(fontSize: 13, color: TZColors.textGray, height: 1.4),
                    maxLines: isExpanded ? null : 2,
                    overflow: isExpanded ? null : TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // 变更统计
                  Row(
                    children: [
                      if (version.featCount > 0) _buildChangeCountChip('新功能', version.featCount, Colors.green),
                      if (version.fixCount > 0) _buildChangeCountChip('修复', version.fixCount, Colors.orange),
                      if (version.improveCount > 0) _buildChangeCountChip('优化', version.improveCount, Colors.blue),
                      if (version.commitHash != null) ...[
                        const Spacer(),
                        Text(
                          version.commitHash!,
                          style: TextStyle(
                            fontSize: 11,
                            color: TZColors.textLight,
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 展开的变更详情
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
            _buildChangesList(version),
          ],
        ],
      ),
    );
  }

  Widget _buildChangeCountChip(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$label $count',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 变更详情列表
  // ═══════════════════════════════════════════════════════

  Widget _buildChangesList(AppVersion version) {
    // 按类别分组
    final grouped = <String, List<ChangelogEntry>>{};
    for (final change in version.changes) {
      grouped.putIfAbsent(change.category, () => []).add(change);
    }

    // 排序：feat > fix > improve > docs > chore
    final order = ['feat', 'fix', 'improve', 'docs', 'chore'];
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final key in sortedKeys) ...[
            // 类别标题
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(
                children: [
                  Icon(_getCategoryIcon(key), size: 16, color: _getCategoryColor(key)),
                  const SizedBox(width: 6),
                  Text(
                    _getCategoryLabel(key),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _getCategoryColor(key),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(key).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${grouped[key]!.length}',
                      style: TextStyle(fontSize: 11, color: _getCategoryColor(key), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            // 变更条目
            for (final change in grouped[key]!) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(key).withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: change.content,
                              style: const TextStyle(fontSize: 13, color: TZColors.textDark, height: 1.4),
                            ),
                            if (change.module != null) ...[
                              TextSpan(
                                text: '  ${change.module}',
                                style: TextStyle(fontSize: 11, color: TZColors.textLight.withOpacity(0.6)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],

          // 版本元信息
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _buildMetaRow('构建号', version.buildNumber),
                _buildMetaRow('开发者', version.developer),
                _buildMetaRow('支持平台', version.platforms.join(' / ')),
                if (version.commitHash != null) _buildMetaRow('Commit', version.commitHash!),
                if (version.forceUpdate) _buildMetaRow('强制更新', '是'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 12, color: TZColors.textGray)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: TZColors.textDark, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 操作方法
  // ═══════════════════════════════════════════════════════

  Future<void> _syncToBackend() async {
    final auth = context.read<AuthService>();
    if (auth.bizToken == null) {
      _showSnackBar('请先登录', isError: true);
      return;
    }

    setState(() => _isSyncing = true);

    final success = await _versionService.syncToBackend(auth.bizToken!);

    setState(() => _isSyncing = false);

    if (success) {
      _showSnackBar('版本数据已同步到后端');
    } else {
      _showSnackBar('同步失败，后端接口可能尚未部署', isError: true);
    }
  }

  void _exportJson() {
    final jsonStr = _versionService.exportAsJson();
    Clipboard.setData(ClipboardData(text: jsonStr));
    _showSnackBar('版本数据 JSON 已复制到剪贴板');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isError ? TZColors.errorRed : TZColors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 样式工具方法
  // ═══════════════════════════════════════════════════════

  Color _getTypeColor(String type) {
    switch (type) {
      case 'major':
        return const Color(0xFF8B5CF6);
      case 'minor':
        return const Color(0xFF3B82F6);
      case 'patch':
        return const Color(0xFFF59E0B);
      case 'hotfix':
        return const Color(0xFFEF4444);
      default:
        return TZColors.textGray;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'feat':
        return const Color(0xFF10B981);
      case 'fix':
        return const Color(0xFFF59E0B);
      case 'improve':
        return const Color(0xFF3B82F6);
      case 'docs':
        return const Color(0xFF8B5CF6);
      case 'chore':
        return const Color(0xFF6B7280);
      default:
        return TZColors.textGray;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'feat':
        return Icons.auto_awesome;
      case 'fix':
        return Icons.build_circle;
      case 'improve':
        return Icons.trending_up;
      case 'docs':
        return Icons.description;
      case 'chore':
        return Icons.settings;
      default:
        return Icons.circle;
    }
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'feat':
        return '新功能';
      case 'fix':
        return '问题修复';
      case 'improve':
        return '优化改进';
      case 'docs':
        return '文档更新';
      case 'chore':
        return '维护';
      default:
        return '其他';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
