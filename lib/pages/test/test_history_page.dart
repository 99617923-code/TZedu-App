/// 途正英语 - 测评历史记录页面
/// 火鹰科技出品
///
/// 分页展示用户的历史测评记录
/// 点击可查看详细结果
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/test_service.dart';
import 'test_result_page.dart';

class TestHistoryPage extends StatefulWidget {
  const TestHistoryPage({super.key});

  @override
  State<TestHistoryPage> createState() => _TestHistoryPageState();
}

class _TestHistoryPageState extends State<TestHistoryPage> {
  final List<TestHistoryItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    final result = await TestService.instance.getHistory(page: _page, pageSize: 10);

    setState(() {
      _isLoading = false;
      if (result.success) {
        _items.addAll(result.list);
        _total = result.total;
        _hasMore = _items.length < _total;
        _page++;
      }
    });
  }

  Future<void> _refresh() async {
    _items.clear();
    _page = 1;
    _hasMore = true;
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.5, -1),
            end: Alignment(0.5, 1),
            colors: [TZColors.bgStart, TZColors.bgPurple, TZColors.bgMid, TZColors.bgEnd],
            stops: [0.0, 0.15, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    ),
                    const Expanded(
                      child: Text(
                        '测评历史',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TZColors.textDark),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 列表
              Expanded(
                child: _items.isEmpty && !_isLoading
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        color: TZColors.primaryPurple,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              _loadMore();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(color: TZColors.primaryPurple)),
                              );
                            }
                            return _buildHistoryItem(_items[index]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.history, size: 36, color: TZColors.textGray),
          ),
          const SizedBox(height: 16),
          const Text('暂无测评记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TZColors.textGray)),
          const SizedBox(height: 8),
          Text('完成一次 AI 分级测评后，记录将显示在这里', style: TextStyle(fontSize: 13, color: TZColors.textGray.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(TestHistoryItem item) {
    final isCompleted = item.status == 'completed';
    final statusLabel = _statusLabel(item.status);
    final statusColor = _statusColor(item.status);

    final minutes = item.totalDuration ~/ 60;
    final seconds = item.totalDuration % 60;
    final timeStr = minutes > 0 ? '$minutes 分 $seconds 秒' : '$seconds 秒';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TestResultPage(sessionId: item.sessionId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
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
            // 级别标签
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isCompleted
                      ? [const Color(0xFF7C3AED), const Color(0xFFA855F7)]
                      : [const Color(0xFF9CA3AF), const Color(0xFFD1D5DB)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  item.levelLabel ?? item.finalLevel ?? '--',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.levelName ?? 'AI 分级测评',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TZColors.textDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.quiz_outlined, size: 13, color: TZColors.textGray.withOpacity(0.6)),
                      const SizedBox(width: 4),
                      Text('${item.questionCount} 题', style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.7))),
                      const SizedBox(width: 16),
                      Icon(Icons.timer_outlined, size: 13, color: TZColors.textGray.withOpacity(0.6)),
                      const SizedBox(width: 4),
                      Text(timeStr, style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.7))),
                    ],
                  ),
                  if (item.completedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(item.completedAt!),
                      style: TextStyle(fontSize: 11, color: TZColors.textGray.withOpacity(0.5)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: TZColors.textLight, size: 20),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return '已完成';
      case 'in_progress':
        return '进行中';
      case 'terminated':
        return '已终止';
      case 'expired':
        return '已过期';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return TZColors.green;
      case 'in_progress':
        return TZColors.blue;
      case 'terminated':
        return const Color(0xFFF59E0B);
      case 'expired':
        return TZColors.textGray;
      default:
        return TZColors.textGray;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
