/// 途正英语 - AI 分级测评服务层
/// 火鹰科技出品
///
/// 职责：
/// 1. 创建测评会话（自适应难度）
/// 2. 提交回答并获取 AI 四维评估
/// 3. 上传录音 / ASR 转写 / TTS 朗读
/// 4. 获取测评结果和历史记录
/// 5. 终止测评会话

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/im_config.dart';
import 'auth_service.dart';

// ═══════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════

/// 测评题目
class TestQuestion {
  final String questionId;
  final String type;
  final String content;
  final int difficulty;
  final List<String>? options;
  final int? timeLimit;

  TestQuestion({
    required this.questionId,
    required this.type,
    required this.content,
    required this.difficulty,
    this.options,
    this.timeLimit,
  });

  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    return TestQuestion(
      questionId: json['questionId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'oral',
      content: json['content']?.toString() ?? '',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      options: json['options'] != null
          ? List<String>.from(json['options'])
          : null,
      timeLimit: (json['timeLimit'] as num?)?.toInt(),
    );
  }
}

/// 测评会话
class TestSession {
  final String sessionId;
  final TestQuestion firstQuestion;
  final int totalQuestions;
  final String? expiresAt;

  TestSession({
    required this.sessionId,
    required this.firstQuestion,
    required this.totalQuestions,
    this.expiresAt,
  });

  factory TestSession.fromJson(Map<String, dynamic> json) {
    return TestSession(
      sessionId: json['sessionId']?.toString() ?? '',
      firstQuestion: TestQuestion.fromJson(json['firstQuestion'] ?? {}),
      totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 10,
      expiresAt: json['expiresAt']?.toString(),
    );
  }
}

/// AI 评估结果
class EvaluationResult {
  final double score;
  final double comprehension;
  final double grammar;
  final double vocabulary;
  final double fluency;
  final String? feedback;

  EvaluationResult({
    required this.score,
    required this.comprehension,
    required this.grammar,
    required this.vocabulary,
    required this.fluency,
    this.feedback,
  });

  factory EvaluationResult.fromJson(Map<String, dynamic> json) {
    return EvaluationResult(
      score: (json['score'] as num?)?.toDouble() ?? 0,
      comprehension: (json['comprehension'] as num?)?.toDouble() ?? 0,
      grammar: (json['grammar'] as num?)?.toDouble() ?? 0,
      vocabulary: (json['vocabulary'] as num?)?.toDouble() ?? 0,
      fluency: (json['fluency'] as num?)?.toDouble() ?? 0,
      feedback: json['feedback']?.toString(),
    );
  }
}

/// 评估响应（含下一步动作）
class EvaluateResponse {
  final EvaluationResult evaluation;
  final String nextAction; // "continue" | "terminate"
  final TestQuestion? nextQuestion;

  EvaluateResponse({
    required this.evaluation,
    required this.nextAction,
    this.nextQuestion,
  });

  factory EvaluateResponse.fromJson(Map<String, dynamic> json) {
    return EvaluateResponse(
      evaluation: EvaluationResult.fromJson(json['evaluation'] ?? {}),
      nextAction: json['nextAction']?.toString() ?? 'terminate',
      nextQuestion: json['nextQuestion'] != null
          ? TestQuestion.fromJson(json['nextQuestion'])
          : null,
    );
  }
}

/// 测评最终结果
class TestResult {
  final String sessionId;
  final String finalLevel;
  final String levelName;
  final String levelLabel;
  final int questionCount;
  final int totalDuration;
  final Map<String, double> scores;
  final List<Map<String, dynamic>> questions;
  final String? recommendation;

  TestResult({
    required this.sessionId,
    required this.finalLevel,
    required this.levelName,
    required this.levelLabel,
    required this.questionCount,
    required this.totalDuration,
    required this.scores,
    required this.questions,
    this.recommendation,
  });

  factory TestResult.fromJson(Map<String, dynamic> json) {
    final scoresJson = json['scores'] as Map<String, dynamic>? ?? {};
    return TestResult(
      sessionId: json['sessionId']?.toString() ?? '',
      finalLevel: json['finalLevel']?.toString() ?? '',
      levelName: json['levelName']?.toString() ?? '',
      levelLabel: json['levelLabel']?.toString() ?? '',
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 0,
      totalDuration: (json['totalDuration'] as num?)?.toInt() ?? 0,
      scores: scoresJson.map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0)),
      questions: List<Map<String, dynamic>>.from(json['questions'] ?? []),
      recommendation: json['recommendation']?.toString(),
    );
  }
}

/// 测评历史条目
class TestHistoryItem {
  final String sessionId;
  final String? finalLevel;
  final String? levelName;
  final String? levelLabel;
  final int questionCount;
  final int totalDuration;
  final String? completedAt;
  final String status;

  TestHistoryItem({
    required this.sessionId,
    this.finalLevel,
    this.levelName,
    this.levelLabel,
    required this.questionCount,
    required this.totalDuration,
    this.completedAt,
    required this.status,
  });

  factory TestHistoryItem.fromJson(Map<String, dynamic> json) {
    return TestHistoryItem(
      sessionId: json['sessionId']?.toString() ?? '',
      finalLevel: json['finalLevel']?.toString(),
      levelName: json['levelName']?.toString(),
      levelLabel: json['levelLabel']?.toString(),
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 0,
      totalDuration: (json['totalDuration'] as num?)?.toInt() ?? 0,
      completedAt: json['completedAt']?.toString(),
      status: json['status']?.toString() ?? 'unknown',
    );
  }
}

// ═══════════════════════════════════════════════════════
// 测评服务
// ═══════════════════════════════════════════════════════

class TestService extends ChangeNotifier {
  static final TestService _instance = TestService._internal();
  static TestService get instance => _instance;
  TestService._internal();

  // 当前测评状态
  TestSession? _currentSession;
  TestSession? get currentSession => _currentSession;

  TestQuestion? _currentQuestion;
  TestQuestion? get currentQuestion => _currentQuestion;

  int _answeredCount = 0;
  int get answeredCount => _answeredCount;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isInTest = false;
  bool get isInTest => _isInTest;

  String? get _token => AuthService.instance.bizToken;

  // ═══════════════════════════════════════════════════════
  // 创建测评会话
  // ═══════════════════════════════════════════════════════

  Future<({bool success, String message, TestSession? session})> startTest({
    String deviceType = 'h5',
  }) async {
    if (_token == null) return (success: false, message: '未登录', session: null);

    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testStartPath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({'deviceType': deviceType}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        _currentSession = TestSession.fromJson(data);
        _currentQuestion = _currentSession!.firstQuestion;
        _answeredCount = 0;
        _isInTest = true;
        notifyListeners();
        return (success: true, message: '测评开始', session: _currentSession);
      }

      return (success: false, message: (body['msg'] ?? '创建测评失败').toString(), session: null);
    } catch (e) {
      _log('创建测评异常: $e');
      return (success: false, message: '网络异常: $e', session: null);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 提交回答并获取评估
  // ═══════════════════════════════════════════════════════

  Future<({bool success, String message, EvaluateResponse? response})> evaluate({
    required String questionId,
    String? audioUrl,
    String? transcription,
    int? answerDuration,
  }) async {
    if (_token == null || _currentSession == null) {
      return (success: false, message: '无效的测评会话', response: null);
    }

    _isLoading = true;
    notifyListeners();

    try {
      final params = <String, dynamic>{
        'sessionId': _currentSession!.sessionId,
        'questionId': questionId,
      };
      if (audioUrl != null) params['audioUrl'] = audioUrl;
      if (transcription != null) params['transcription'] = transcription;
      if (answerDuration != null) params['answerDuration'] = answerDuration;

      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testEvaluatePath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode(params),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        final evalResponse = EvaluateResponse.fromJson(data);

        _answeredCount++;

        if (evalResponse.nextAction == 'continue' && evalResponse.nextQuestion != null) {
          _currentQuestion = evalResponse.nextQuestion;
        } else {
          _currentQuestion = null;
          _isInTest = false;
        }

        notifyListeners();
        return (success: true, message: '评估完成', response: evalResponse);
      }

      return (success: false, message: (body['msg'] ?? '评估失败').toString(), response: null);
    } catch (e) {
      _log('评估异常: $e');
      return (success: false, message: '网络异常: $e', response: null);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 获取测评结果
  // ═══════════════════════════════════════════════════════

  Future<({bool success, String message, TestResult? result})> getResult(String sessionId) async {
    if (_token == null) return (success: false, message: '未登录', result: null);

    try {
      final response = await http.get(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testResultPath}/$sessionId'),
        headers: IMConfig.authHeaders(_token!),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        return (success: true, message: '获取成功', result: TestResult.fromJson(data));
      }

      return (success: false, message: (body['msg'] ?? '获取失败').toString(), result: null);
    } catch (e) {
      _log('获取结果异常: $e');
      return (success: false, message: '网络异常: $e', result: null);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 测评历史
  // ═══════════════════════════════════════════════════════

  Future<({bool success, int total, List<TestHistoryItem> list})> getHistory({
    int page = 1,
    int pageSize = 10,
  }) async {
    if (_token == null) return (success: false, total: 0, list: <TestHistoryItem>[]);

    try {
      final uri = Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testHistoryPath}')
          .replace(queryParameters: {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      });

      final response = await http.get(
        uri,
        headers: IMConfig.authHeaders(_token!),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        final list = (data['list'] as List<dynamic>?)
            ?.map((e) => TestHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList() ?? [];
        return (success: true, total: (data['total'] as num?)?.toInt() ?? 0, list: list);
      }

      return (success: false, total: 0, list: <TestHistoryItem>[]);
    } catch (e) {
      _log('获取历史异常: $e');
      return (success: false, total: 0, list: <TestHistoryItem>[]);
    }
  }

  // ═══════════════════════════════════════════════════════
  // TTS 文本转语音
  // ═══════════════════════════════════════════════════════

  Future<String?> textToSpeech(String text, {String voice = 'en-US-female', double speed = 0.85}) async {
    if (_token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testTtsPath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          'text': text,
          'voice': voice,
          'speed': speed,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        return data['audioUrl']?.toString();
      }

      return null;
    } catch (e) {
      _log('TTS 异常: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 终止测评
  // ═══════════════════════════════════════════════════════

  Future<bool> terminateTest({String reason = 'user_quit'}) async {
    if (_token == null || _currentSession == null) return false;

    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testTerminatePath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          'sessionId': _currentSession!.sessionId,
          'reason': reason,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        _isInTest = false;
        _currentQuestion = null;
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      _log('终止测评异常: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // ASR 语音转文字
  // ═══════════════════════════════════════════════════════

  Future<({bool success, String text, double confidence})> transcribe(String audioUrl) async {
    if (_token == null) return (success: false, text: '', confidence: 0.0);

    try {
      final response = await http.post(
        Uri.parse('${IMConfig.apiBaseUrl}${IMConfig.testTranscribePath}'),
        headers: IMConfig.authHeaders(_token!),
        body: jsonEncode({
          'audioUrl': audioUrl,
          'language': 'en',
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (body['code'] == 200) {
        final data = body['data'] as Map<String, dynamic>;
        return (
          success: true,
          text: data['text']?.toString() ?? '',
          confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
        );
      }

      return (success: false, text: '', confidence: 0.0);
    } catch (e) {
      _log('ASR 异常: $e');
      return (success: false, text: '', confidence: 0.0);
    }
  }

  /// 重置测评状态
  void reset() {
    _currentSession = null;
    _currentQuestion = null;
    _answeredCount = 0;
    _isInTest = false;
    _isLoading = false;
    notifyListeners();
  }

  void _log(String message) {
    debugPrint('[TestService] $message');
  }
}
