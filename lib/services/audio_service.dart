/// 语音录制和播放服务
/// 火鹰科技出品
///
/// 技术方案：
/// - 录音：record 包（AudioRecorder）— 全平台支持
/// - 播放：audioplayers 包（AudioPlayer）— 全平台支持
/// - 权限：permission_handler
///
/// 重要：record 包要求每次录音创建新的 AudioRecorder 实例，
/// 录音结束后必须 dispose。这是官方文档明确要求的用法。
///
/// 使用方式：
///   final service = TZAudioService.instance;
///   await service.startRecording();
///   final result = await service.stopRecording();
///   await service.playAudio(url, messageId: id);

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 录音结果
class RecordingResult {
  final String filePath;
  final int durationMs; // 毫秒
  final int fileSize; // 文件大小（字节）

  RecordingResult({
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
  });
}

/// 语音服务状态
enum TZAudioState {
  idle, // 空闲
  recording, // 录音中
  playing, // 播放中
}

class TZAudioService extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════
  // 单例
  // ═══════════════════════════════════════════════════════

  static final TZAudioService _instance = TZAudioService._internal();
  static TZAudioService get instance => _instance;
  TZAudioService._internal();

  // ═══════════════════════════════════════════════════════
  // 平台判断
  // ═══════════════════════════════════════════════════════

  /// 是否是移动端（iOS/Android）— 桌面端已隐藏录音按钮
  bool get _isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

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
  // 内部变量 — 录音（record 包）
  // ═══════════════════════════════════════════════════════

  /// 当前录音器实例（每次录音创建新实例，录音结束后 dispose）
  AudioRecorder? _recorder;
  Timer? _secondsTimer; // UI 秒数显示
  Timer? _amplitudeTimer; // 振幅检测
  DateTime? _recordingStartTime; // 录音开始时间
  String? _currentRecordingPath; // 当前录音文件路径

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;
  /// 最小录音时长（毫秒），低于此时长不发送
  static const int minRecordingDurationMs = 1000;

  // ═══════════════════════════════════════════════════════
  // 内部变量 — 播放（audioplayers，全平台）
  // ═══════════════════════════════════════════════════════

  AudioPlayer? _currentPlayer;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerPositionSubscription;
  StreamSubscription? _playerDurationSubscription;
  Duration? _totalDuration;

  // ═══════════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════════

  /// 初始化录音器（record 包不需要预初始化，每次录音时创建新实例）
  Future<void> initRecorder() async {
    _log('录音器使用 record 包，无需预初始化');
  }

  /// 初始化播放器（全平台）
  void initAudioPlayer() {
    _setupSpeaker();
  }

  /// 设置播放器音频上下文
  Future<void> _setupSpeaker() async {
    try {
      final audioContext = AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.media,
          audioMode: AndroidAudioMode.normal,
          isSpeakerphoneOn: true,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      );
      await AudioPlayer.global.setAudioContext(audioContext);
      _log('播放器音频上下文设置成功');
    } catch (e) {
      _log('设置播放器音频上下文失败（桌面端可忽略）: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 权限管理（使用 permission_handler）
  // ═══════════════════════════════════════════════════════

  /// 请求麦克风权限
  Future<bool> requestMicrophonePermission() async {
    if (!_isMobile) return false;
    try {
      final status = await Permission.microphone.request();
      _log('麦克风权限状态: $status');
      return status.isGranted;
    } catch (e) {
      _log('请求麦克风权限异常: $e');
      return false;
    }
  }

  /// 检查麦克风权限是否已授权
  Future<bool> isMicrophoneGranted() async {
    if (!_isMobile) return false;
    return await Permission.microphone.isGranted;
  }

  /// 检查麦克风权限是否被永久拒绝
  Future<bool> isMicrophonePermanentlyDenied() async {
    if (!_isMobile) return false;
    return await Permission.microphone.isPermanentlyDenied;
  }

  // ═══════════════════════════════════════════════════════
  // 录音功能（使用 record 包，仅移动端）
  // ═══════════════════════════════════════════════════════

  /// 开始录音
  Future<bool> startRecording() async {
    if (!_isMobile) {
      _log('桌面端不支持录音');
      return false;
    }

    if (_state != TZAudioState.idle) {
      _log('当前状态不允许录音: $_state');
      return false;
    }

    try {
      // 每次录音创建全新的 AudioRecorder 实例（record 包官方要求）
      _recorder?.dispose();
      _recorder = AudioRecorder();

      // 检查权限（record 包自带的权限检查）
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        _log('没有录音权限');
        _recorder?.dispose();
        _recorder = null;
        return false;
      }

      // 获取临时目录，生成录音文件路径
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/tz_audio_$timestamp.m4a';

      // 录音配置：使用默认的 aacLc 编码，44100Hz，128kbps
      // 这是 record 包的默认配置，在所有平台上兼容性最好
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1,
      );

      // 开始录音
      await _recorder!.start(config, path: _currentRecordingPath!);

      _state = TZAudioState.recording;
      _recordingSeconds = 0;
      _amplitude = 0.0;
      _recordingStartTime = DateTime.now();

      // 启动秒数计时器（用于 UI 显示）
      _secondsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        notifyListeners();

        if (_recordingSeconds >= maxRecordingDuration) {
          _log('录音达到最大时长，自动停止');
          _secondsTimer?.cancel();
        }
      });

      // 启动振幅检测（用于录音波形 UI）
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
        try {
          if (_recorder != null && _state == TZAudioState.recording) {
            final amp = await _recorder!.getAmplitude();
            // amp.current 是 dBFS，范围约 -160 到 0
            // 转换为 0.0 - 1.0 的范围
            final dBFS = amp.current;
            if (dBFS.isFinite && dBFS > -160) {
              final newAmplitude = ((dBFS + 50) / 50).clamp(0.0, 1.0);
              if ((newAmplitude - _amplitude).abs() > 0.03) {
                _amplitude = newAmplitude;
                notifyListeners();
              }
            }
          }
        } catch (_) {
          // 忽略振幅获取异常
        }
      });

      notifyListeners();
      _log('开始录音: $_currentRecordingPath');
      return true;
    } catch (e) {
      _log('开始录音失败: $e');
      _recorder?.dispose();
      _recorder = null;
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
      _secondsTimer?.cancel();
      _amplitudeTimer?.cancel();

      // 停止录音，返回文件路径
      final filePath = await _recorder!.stop();

      // 计算录音时长
      final durationMs = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds
          : 0;

      // dispose 录音器实例（record 包要求）
      _recorder?.dispose();
      _recorder = null;

      _state = TZAudioState.idle;
      _amplitude = 0.0;
      notifyListeners();

      _log('停止录音, 路径: $filePath, 时长: ${durationMs}ms');

      if (filePath == null || filePath.isEmpty) {
        _log('录音文件路径为空');
        return null;
      }

      // 检查最小时长
      if (durationMs < minRecordingDurationMs) {
        _log('录音时长不足 ${minRecordingDurationMs}ms (实际: ${durationMs}ms)，取消发送');
        _deleteFile(filePath);
        return null;
      }

      // 验证文件
      final file = File(filePath);
      if (!await file.exists()) {
        _log('录音文件不存在: $filePath');
        return null;
      }

      final fileSize = await file.length();
      _log('录音文件大小: $fileSize bytes');

      if (fileSize < 100) {
        _log('录音文件太小（<100 bytes），可能录音失败');
        _deleteFile(filePath);
        return null;
      }

      return RecordingResult(
        filePath: filePath,
        durationMs: durationMs,
        fileSize: fileSize,
      );
    } catch (e) {
      _log('停止录音失败: $e');
      _recorder?.dispose();
      _recorder = null;
      _state = TZAudioState.idle;
      notifyListeners();
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (_state != TZAudioState.recording) return;

    try {
      _secondsTimer?.cancel();
      _amplitudeTimer?.cancel();

      // 取消录音（record 包的 cancel 会自动删除文件）
      await _recorder?.cancel();

      // dispose 录音器实例
      _recorder?.dispose();
      _recorder = null;

      _state = TZAudioState.idle;
      _recordingSeconds = 0;
      _amplitude = 0.0;
      _recordingStartTime = null;
      notifyListeners();
      _log('录音已取消');
    } catch (e) {
      _log('取消录音失败: $e');
      _recorder?.dispose();
      _recorder = null;
      _state = TZAudioState.idle;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 播放功能（audioplayers，全平台）
  // ═══════════════════════════════════════════════════════

  /// 播放语音消息
  /// [source] 可以是本地文件路径或远程 URL
  /// [messageId] 用于标识当前播放的消息
  /// [durationMs] 音频总时长（毫秒），用于计算进度
  Future<void> playAudio(String source, {String? messageId, int? durationMs}) async {
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
      _setupSpeaker();

      // 每次播放创建新的 AudioPlayer 实例
      _currentPlayer?.dispose();
      _currentPlayer = AudioPlayer();

      final player = _currentPlayer!;

      _log('准备播放: $source');

      _state = TZAudioState.playing;
      _playingMessageId = messageId;
      _playProgress = 0.0;
      _totalDuration = durationMs != null ? Duration(milliseconds: durationMs) : null;
      notifyListeners();

      // 监听播放状态
      _playerStateSubscription?.cancel();
      _playerStateSubscription = player.onPlayerStateChanged.listen((event) {
        if (event == PlayerState.stopped || event == PlayerState.completed) {
          _onPlaybackCompleted();
        }
      });

      // 监听播放进度
      _playerPositionSubscription?.cancel();
      _playerPositionSubscription = player.onPositionChanged.listen((position) {
        if (_totalDuration != null && _totalDuration!.inMilliseconds > 0) {
          _playProgress = (position.inMilliseconds / _totalDuration!.inMilliseconds).clamp(0.0, 1.0);
          notifyListeners();
        }
      });

      // 获取时长
      _playerDurationSubscription?.cancel();
      _playerDurationSubscription = player.onDurationChanged.listen((duration) {
        if (_totalDuration == null || _totalDuration!.inMilliseconds == 0) {
          _totalDuration = duration;
        }
      });

      // 播放（先尝试 URL，再尝试本地文件）
      Source audioSource;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        audioSource = UrlSource(source);
      } else {
        // 本地文件
        final file = File(source);
        if (!await file.exists()) {
          _log('本地音频文件不存在: $source');
          _state = TZAudioState.idle;
          _playingMessageId = null;
          notifyListeners();
          return;
        }
        audioSource = DeviceFileSource(source);
      }

      await player.play(audioSource);
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
      _playerDurationSubscription?.cancel();

      await _currentPlayer?.stop();

      _state = TZAudioState.idle;
      _playingMessageId = null;
      _playProgress = 0.0;
      notifyListeners();
      _log('停止播放');
    } catch (e) {
      _log('停止播放失败: $e');
    }
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
  // 工具方法
  // ═══════════════════════════════════════════════════════

  /// 删除临时文件
  void _deleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        _log('已删除临时文件: $path');
      }
    } catch (e) {
      _log('删除文件失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 资源释放
  // ═══════════════════════════════════════════════════════

  /// 释放所有资源
  void releaseAll() {
    _secondsTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();

    // 释放录音器
    _recorder?.dispose();
    _recorder = null;

    // 释放播放器
    _currentPlayer?.dispose();
    _currentPlayer = null;

    _state = TZAudioState.idle;
    _playingMessageId = null;
    _playProgress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _secondsTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();

    _recorder?.dispose();
    _recorder = null;

    _currentPlayer?.dispose();
    _currentPlayer = null;

    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 日志
  // ═══════════════════════════════════════════════════════

  void _log(String msg) {
    debugPrint('[TZAudioService] $msg');
  }
}
