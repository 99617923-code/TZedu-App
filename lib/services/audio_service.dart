/// 语音录制和播放服务
/// 火鹰科技出品
///
/// 职责：
/// 1. 录制语音消息（使用 record 包，全平台支持）
/// 2. 播放语音消息（使用 just_audio 包，全平台支持）
/// 3. 管理录音和播放状态
///
/// 使用方式：
///   final service = TZAudioService.instance;
///   await service.startRecording();
///   final result = await service.stopRecording();
///   await service.playAudio(url);

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 录音结果
class RecordingResult {
  final String filePath;
  final int durationMs; // 毫秒

  RecordingResult({required this.filePath, required this.durationMs});
}

/// 语音服务状态
enum TZAudioState {
  idle,       // 空闲
  recording,  // 录音中
  playing,    // 播放中
}

class TZAudioService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final TZAudioService _instance = TZAudioService._internal();
  static TZAudioService get instance => _instance;
  TZAudioService._internal();

  // ═══════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════

  TZAudioState _state = TZAudioState.idle;
  TZAudioState get state => _state;

  bool get isRecording => _state == TZAudioState.recording;
  bool get isPlaying => _state == TZAudioState.playing;

  /// 当前录音时长（秒）
  int _recordingSeconds = 0;
  int get recordingSeconds => _recordingSeconds;

  /// 当前录音振幅（0.0 - 1.0）
  double _amplitude = 0.0;
  double get amplitude => _amplitude;

  /// 当前正在播放的消息 ID
  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;

  /// 播放进度（0.0 - 1.0）
  double _playProgress = 0.0;
  double get playProgress => _playProgress;

  // ═══════════════════════════════════════════════════════
  // 内部变量
  // ═══════════════════════════════════════════════════════

  AudioRecorder? _recorder;
  AudioPlayer? _player;
  Timer? _recordingTimer;
  Timer? _amplitudeTimer;
  DateTime? _recordingStartTime;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerPositionSubscription;
  Duration? _totalDuration;

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;

  /// 最小录音时长（秒），低于此时长不发送
  static const int minRecordingDuration = 1;

  // ═══════════════════════════════════════════════════════
  // 录音功能
  // ═══════════════════════════════════════════════════════

  /// 检查麦克风权限
  Future<bool> checkPermission() async {
    _recorder ??= AudioRecorder();
    return await _recorder!.hasPermission();
  }

  /// 开始录音
  Future<bool> startRecording() async {
    if (_state != TZAudioState.idle) {
      _log('当前状态不允许录音: $_state');
      return false;
    }

    try {
      _recorder ??= AudioRecorder();

      // 检查权限
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        _log('没有麦克风权限');
        return false;
      }

      // 获取临时目录
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(dir.path, 'voice_$timestamp.m4a');

      // 配置录音参数
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1, // 单声道，语音消息足够
      );

      // 开始录音
      await _recorder!.start(config, path: filePath);

      _state = TZAudioState.recording;
      _recordingSeconds = 0;
      _recordingStartTime = DateTime.now();
      _amplitude = 0.0;

      // 启动计时器
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        notifyListeners();

        // 超过最大时长自动停止
        if (_recordingSeconds >= maxRecordingDuration) {
          _log('录音达到最大时长，自动停止');
          // 不在这里调用 stopRecording，由外部处理
          _recordingTimer?.cancel();
        }
      });

      // 启动振幅检测（降低频率到 300ms，且仅在变化超过阈值时通知 UI，
      // 避免 iOS 上因高频 notifyListeners 导致计时器显示跳动）
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
        try {
          final amp = await _recorder!.getAmplitude();
          // amp.current 范围是 -160 到 0 (dBFS)，转换为 0-1
          final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
          // 仅在振幅变化超过 0.05 时才刷新 UI，减少不必要的重建
          if ((normalized - _amplitude).abs() > 0.05) {
            _amplitude = normalized;
            notifyListeners();
          }
        } catch (_) {}
      });

      notifyListeners();
      _log('开始录音: $filePath');
      return true;
    } catch (e) {
      _log('开始录音失败: $e');
      _state = TZAudioState.idle;
      notifyListeners();
      return false;
    }
  }

  /// 停止录音并返回结果
  Future<RecordingResult?> stopRecording() async {
    if (_state != TZAudioState.recording) {
      _log('当前不在录音状态');
      return null;
    }

    try {
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();

      final filePath = await _recorder!.stop();

      // 计算实际录音时长
      final durationMs = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0;

      _state = TZAudioState.idle;
      _amplitude = 0.0;
      notifyListeners();

      if (filePath == null || filePath.isEmpty) {
        _log('录音文件路径为空');
        return null;
      }

      // 检查最小时长
      final durationSeconds = (durationMs / 1000).round();
      if (durationSeconds < minRecordingDuration) {
        _log('录音时长不足 ${minRecordingDuration} 秒，取消发送');
        // 删除文件
        try {
          final file = File(filePath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return null;
      }

      _log('录音完成: $filePath, 时长: ${durationMs}ms');
      return RecordingResult(filePath: filePath, durationMs: durationMs);
    } catch (e) {
      _log('停止录音失败: $e');
      _state = TZAudioState.idle;
      notifyListeners();
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (_state != TZAudioState.recording) return;

    try {
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();

      final filePath = await _recorder!.stop();

      // 删除录音文件
      if (filePath != null && filePath.isNotEmpty) {
        try {
          final file = File(filePath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }

      _state = TZAudioState.idle;
      _recordingSeconds = 0;
      _amplitude = 0.0;
      notifyListeners();
      _log('录音已取消');
    } catch (e) {
      _log('取消录音失败: $e');
      _state = TZAudioState.idle;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 播放功能
  // ═══════════════════════════════════════════════════════

  /// 播放语音消息
  /// [source] 可以是本地文件路径或远程 URL
  /// [messageId] 用于标识当前播放的消息
  Future<void> playAudio(String source, {String? messageId}) async {
    // 如果正在播放同一条消息，则停止
    if (_state == TZAudioState.playing && _playingMessageId == messageId) {
      await stopPlaying();
      return;
    }

    // 如果正在播放其他消息，先停止
    if (_state == TZAudioState.playing) {
      await stopPlaying();
    }

    // 如果正在录音，不允许播放
    if (_state == TZAudioState.recording) {
      _log('录音中，无法播放');
      return;
    }

    try {
      _player ??= AudioPlayer();

      // 设置音频源
      if (source.startsWith('http://') || source.startsWith('https://')) {
        await _player!.setUrl(source);
      } else {
        await _player!.setFilePath(source);
      }

      _state = TZAudioState.playing;
      _playingMessageId = messageId;
      _playProgress = 0.0;
      _totalDuration = _player!.duration;
      notifyListeners();

      // 监听播放状态
      _playerStateSubscription?.cancel();
      _playerStateSubscription = _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onPlaybackCompleted();
        }
      });

      // 监听播放进度
      _playerPositionSubscription?.cancel();
      _playerPositionSubscription = _player!.positionStream.listen((position) {
        if (_totalDuration != null && _totalDuration!.inMilliseconds > 0) {
          _playProgress = (position.inMilliseconds / _totalDuration!.inMilliseconds).clamp(0.0, 1.0);
          notifyListeners();
        }
      });

      // 开始播放
      await _player!.play();
      _log('开始播放: $source');
    } catch (e) {
      _log('播放失败: $e');
      _state = TZAudioState.idle;
      _playingMessageId = null;
      _playProgress = 0.0;
      notifyListeners();
    }
  }

  /// 停止播放
  Future<void> stopPlaying() async {
    try {
      _playerStateSubscription?.cancel();
      _playerPositionSubscription?.cancel();
      await _player?.stop();
    } catch (_) {}

    _state = TZAudioState.idle;
    _playingMessageId = null;
    _playProgress = 0.0;
    notifyListeners();
    _log('停止播放');
  }

  /// 播放完成回调
  void _onPlaybackCompleted() {
    _state = TZAudioState.idle;
    _playingMessageId = null;
    _playProgress = 0.0;
    notifyListeners();
    _log('播放完成');
  }

  // ═══════════════════════════════════════════════════════
  // 资源释放
  // ═══════════════════════════════════════════════════════

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _recorder?.dispose();
    _player?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 日志
  // ═══════════════════════════════════════════════════════

  void _log(String msg) {
    debugPrint('[TZAudioService] $msg');
  }
}
