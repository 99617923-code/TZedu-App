/// 途正英语 - 测评结果详情页
/// 火鹰科技出品
///
/// 展示：最终级别、四维雷达图、每题详细评估、学习建议
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/test_service.dart';

class TestResultPage extends StatefulWidget {
  final String sessionId;
  const TestResultPage({super.key, required this.sessionId});

  @override
  State<TestResultPage> createState() => _TestResultPageState();
}

class _TestResultPageState extends State<TestResultPage> {
  bool _isLoading = true;
  TestResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  Future<void> _loadResult() async {
    setState(() => _isLoading = true);

    final res = await TestService.instance.getResult(widget.sessionId);

    setState(() {
      _isLoading = false;
      if (res.success && res.result != null) {
        _result = res.result;
      } else {
        _errorMessage = res.message;
      }
    });
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: TZColors.primaryPurple))
              : _errorMessage != null
                  ? _buildError()
                  : _buildResult(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: TZColors.errorRed),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: TZColors.errorRed)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadResult,
            style: ElevatedButton.styleFrom(backgroundColor: TZColors.primaryPurple),
            child: const Text('重试', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    return CustomScrollView(
      slivers: [
        // 顶部栏
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                ),
                const Expanded(
                  child: Text(
                    '测评报告',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TZColors.textDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ),

        // 级别卡片
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _buildLevelCard(r),
          ),
        ),

        // 四维得分
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _buildScoresCard(r),
          ),
        ),

        // 统计信息
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _buildStatsCard(r),
          ),
        ),

        // 学习建议
        if (r.recommendation != null && r.recommendation!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildRecommendationCard(r.recommendation!),
            ),
          ),

        // 题目详情
        if (r.questions.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildQuestionsCard(r),
            ),
          ),

        // 底部操作
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TZColors.primaryPurple,
                      side: const BorderSide(color: TZColors.primaryPurple),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('返回首页', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // 可以在这里导航到重新测评
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TZColors.primaryPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('再次测评', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelCard(TestResult r) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('你的英语水平', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            r.levelLabel.isNotEmpty ? r.levelLabel : r.finalLevel,
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            r.levelName,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '综合得分 ${(r.scores['overall'] ?? 0).toStringAsFixed(1)}',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoresCard(TestResult r) {
    final dimensions = [
      ('理解力', r.scores['comprehension'] ?? 0, Icons.hearing, const Color(0xFF3B82F6)),
      ('语法', r.scores['grammar'] ?? 0, Icons.spellcheck, const Color(0xFF10B981)),
      ('词汇', r.scores['vocabulary'] ?? 0, Icons.book, const Color(0xFFF59E0B)),
      ('流利度', r.scores['fluency'] ?? 0, Icons.record_voice_over, const Color(0xFFEF4444)),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('四维评估', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TZColors.textDark)),
          const SizedBox(height: 16),
          ...dimensions.map((d) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: d.$4.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(d.$3, size: 16, color: d.$4),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 48,
                    child: Text(d.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TZColors.textDark)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: d.$2 / 100,
                        backgroundColor: const Color(0xFFF3F4F6),
                        valueColor: AlwaysStoppedAnimation<Color>(d.$4),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 40,
                    child: Text(
                      d.$2.toStringAsFixed(0),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: d.$4),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatsCard(TestResult r) {
    final minutes = r.totalDuration ~/ 60;
    final seconds = r.totalDuration % 60;
    final timeStr = minutes > 0 ? '$minutes 分 $seconds 秒' : '$seconds 秒';

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          _buildStatItem('答题数', '${r.questionCount}', Icons.quiz_outlined),
          _buildStatDivider(),
          _buildStatItem('用时', timeStr, Icons.timer_outlined),
          _buildStatDivider(),
          _buildStatItem('级别', r.finalLevel, Icons.trending_up),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: TZColors.primaryPurple),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TZColors.textDark)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 40, color: const Color(0xFFF3F4F6));
  }

  Widget _buildRecommendationCard(String recommendation) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TZColors.green.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: TZColors.green, size: 20),
              SizedBox(width: 8),
              Text('学习建议', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TZColors.green)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recommendation,
            style: const TextStyle(fontSize: 14, color: TZColors.textDark, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsCard(TestResult r) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('题目详情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TZColors.textDark)),
          const SizedBox(height: 12),
          ...r.questions.asMap().entries.map((entry) {
            final i = entry.key;
            final q = entry.value;
            final score = (q['evaluation']?['score'] as num?)?.toDouble() ?? 0;
            final content = q['content']?.toString() ?? '';
            final answer = q['answer']?.toString() ?? q['transcription']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: TZColors.primaryPurple.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: TZColors.primaryPurple),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          content,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TZColors.textDark),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _scoreColor(score).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          score.toStringAsFixed(0),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _scoreColor(score)),
                        ),
                      ),
                    ],
                  ),
                  if (answer.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '回答: $answer',
                      style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.7)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 80) return TZColors.green;
    if (score >= 60) return const Color(0xFFF59E0B);
    return TZColors.errorRed;
  }
}
