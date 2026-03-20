/// 途正英语 - AI 分级测评页面
/// 火鹰科技出品
///
/// 完整测评流程：
/// 1. 开始测评（创建会话）
/// 2. 逐题作答（文字输入，后续支持录音）
/// 3. AI 实时评估 + 自适应难度
/// 4. 测评完成 → 跳转结果页
import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/test_service.dart';
import 'test_result_page.dart';

class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> with TickerProviderStateMixin {
  final _answerController = TextEditingController();
  final _testService = TestService.instance;

  bool _isStarting = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  EvaluateResponse? _lastEvaluation;

  // 计时器
  Timer? _timer;
  int _elapsedSeconds = 0;
  int _questionStartTime = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _timer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 开始测评
  // ═══════════════════════════════════════════════════════

  Future<void> _startTest() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    final result = await _testService.startTest();

    setState(() => _isStarting = false);

    if (result.success) {
      _startTimer();
      _questionStartTime = _elapsedSeconds;
      _fadeController.forward(from: 0);
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 提交回答
  // ═══════════════════════════════════════════════════════

  Future<void> _submitAnswer() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      setState(() => _errorMessage = '请输入你的回答');
      return;
    }

    final question = _testService.currentQuestion;
    if (question == null) return;

    final duration = (_elapsedSeconds - _questionStartTime) * 1000;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await _testService.evaluate(
      questionId: question.questionId,
      transcription: answer,
      answerDuration: duration,
    );

    setState(() => _isSubmitting = false);

    if (result.success && result.response != null) {
      _lastEvaluation = result.response;
      _answerController.clear();

      if (result.response!.nextAction == 'terminate') {
        // 测评结束，跳转结果页
        _timer?.cancel();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TestResultPage(
                sessionId: _testService.currentSession!.sessionId,
              ),
            ),
          );
        }
      } else {
        // 继续下一题
        _questionStartTime = _elapsedSeconds;
        _fadeController.forward(from: 0);
      }
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 终止测评
  // ═══════════════════════════════════════════════════════

  Future<void> _terminateTest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认终止'),
        content: const Text('终止后无法继续答题，但可以查看已答题目的评估结果。确定要终止吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续答题', style: TextStyle(color: TZColors.textGray)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('终止测评', style: TextStyle(color: TZColors.errorRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _testService.terminateTest();
      _timer?.cancel();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TestResultPage(
              sessionId: _testService.currentSession!.sessionId,
            ),
          ),
        );
      }
    }
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════

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
          child: _testService.isInTest ? _buildTestingUI() : _buildStartUI(),
        ),
      ),
    );
  }

  // ═══ 开始测评界面 ═══
  Widget _buildStartUI() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图标
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.psychology, size: 48, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'AI 智能分级测评',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: TZColors.textDark),
              ),
              const SizedBox(height: 8),
              Text(
                '基于 CAT 自适应算法，精准评估你的英语水平',
                style: TextStyle(fontSize: 14, color: TZColors.textGray.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // 说明卡片
              _buildInfoCard(),
              const SizedBox(height: 32),

              // 开始按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isStarting ? null : _startTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TZColors.primaryPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isStarting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('开始测评', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TZColors.errorRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: TZColors.errorRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: const TextStyle(color: TZColors.errorRed, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final items = [
      ('约 8-15 道题', Icons.quiz_outlined, '根据你的水平自适应调整'),
      ('约 10-20 分钟', Icons.timer_outlined, '无需额外准备，随时开始'),
      ('四维评估', Icons.analytics_outlined, '理解力 / 语法 / 词汇 / 流利度'),
      ('AI 智能评分', Icons.smart_toy_outlined, '精准定位你的英语级别'),
    ];

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
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: TZColors.primaryPurple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.$2, size: 18, color: TZColors.primaryPurple),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TZColors.textDark)),
                      Text(item.$3, style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.7))),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══ 测评进行中界面 ═══
  Widget _buildTestingUI() {
    final question = _testService.currentQuestion;
    if (question == null) return const SizedBox.shrink();

    return Column(
      children: [
        // 顶部状态栏
        _buildTestHeader(),
        // 题目 + 输入区
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    // 题目卡片
                    _buildQuestionCard(question),
                    const SizedBox(height: 16),
                    // 上一题评估反馈
                    if (_lastEvaluation != null) _buildFeedbackCard(_lastEvaluation!),
                    if (_lastEvaluation != null) const SizedBox(height: 16),
                    // 回答输入区
                    _buildAnswerInput(),
                    const SizedBox(height: 16),
                    // 错误提示
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TZColors.errorRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_errorMessage!, style: const TextStyle(color: TZColors.errorRed, fontSize: 13)),
                      ),
                    const SizedBox(height: 16),
                    // 提交按钮
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        border: const Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // 返回/终止
          IconButton(
            onPressed: _terminateTest,
            icon: const Icon(Icons.close, color: TZColors.textGray),
            tooltip: '终止测评',
          ),
          const SizedBox(width: 8),
          // 进度
          Expanded(
            child: Column(
              children: [
                Text(
                  '第 ${_testService.answeredCount + 1} 题',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TZColors.textDark),
                ),
                const SizedBox(height: 4),
                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _testService.currentSession != null
                        ? (_testService.answeredCount + 1) / _testService.currentSession!.totalQuestions
                        : 0,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: const AlwaysStoppedAnimation<Color>(TZColors.primaryPurple),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 计时
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: TZColors.primaryPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: TZColors.primaryPurple),
                const SizedBox(width: 4),
                Text(
                  _formatTime(_elapsedSeconds),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TZColors.primaryPurple),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(TestQuestion question) {
    final difficultyLabel = ['', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
    final label = question.difficulty > 0 && question.difficulty < difficultyLabel.length
        ? difficultyLabel[question.difficulty]
        : 'L${question.difficulty}';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 难度标签
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '难度 $label',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  question.type == 'oral' ? '口语' : question.type,
                  style: const TextStyle(color: TZColors.primaryPurple, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              if (question.timeLimit != null) ...[
                const Spacer(),
                Icon(Icons.access_time, size: 14, color: TZColors.textGray.withOpacity(0.6)),
                const SizedBox(width: 4),
                Text(
                  '${question.timeLimit}s',
                  style: TextStyle(fontSize: 12, color: TZColors.textGray.withOpacity(0.6)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // 题目内容
          Text(
            question.content,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TZColors.textDark, height: 1.6),
          ),
          // 选项（如果有）
          if (question.options != null && question.options!.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...question.options!.asMap().entries.map((entry) {
              final idx = entry.key;
              final option = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
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
                            String.fromCharCode(65 + idx),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TZColors.primaryPurple),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(option, style: const TextStyle(fontSize: 14, color: TZColors.textDark)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedbackCard(EvaluateResponse eval) {
    final e = eval.evaluation;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TZColors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TZColors.green.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: TZColors.green, size: 18),
              const SizedBox(width: 8),
              Text(
                '上一题得分: ${e.score.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TZColors.green),
              ),
            ],
          ),
          if (e.feedback != null && e.feedback!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              e.feedback!,
              style: TextStyle(fontSize: 13, color: TZColors.textGray.withOpacity(0.8), height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswerInput() {
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
      child: TextField(
        controller: _answerController,
        maxLines: 5,
        minLines: 3,
        style: const TextStyle(fontSize: 15, color: TZColors.textDark, height: 1.6),
        decoration: InputDecoration(
          hintText: '请用英文输入你的回答...',
          hintStyle: TextStyle(color: TZColors.textGray.withOpacity(0.5)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: TZColors.primaryPurple, width: 1.5),
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitAnswer,
        style: ElevatedButton.styleFrom(
          backgroundColor: TZColors.primaryPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('提交回答', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
