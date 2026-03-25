/// 语音录制和播放服务
/// 火鹰科技出品
///
/// 参考网易云信官方 IM UIKit Flutter Demo 实现：
/// - 录音：flutter_sound（FlutterSoundRecorder）
/// - 播放：audioplayers（AudioPlayer）
/// - 权限：permission_handler
///
/// 使用方式：
///   final service = TZAudioService.instance;
///   await service.startRecording();
///   final result = await service.stopRecording();
///   await service.playAudio(url, messageId: id);

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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
  // 内部变量 — 录音（flutter_sound，参考官方 Demo）
  // ═══════════════════════════════════════════════════════

  FlutterSoundRecorder? _recorder;
  bool _recorderInitialized = false;
  StreamSubscription? _recorderSubscription;
  int _recordingDurationMs = 0; // 录音时长（毫秒），由 onProgress 回调更新
  Timer? _secondsTimer; // 用于 UI 显示的秒数计时器

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;
  /// 最小录音时长（毫秒），低于此时长不发送
  static const int minRecordingDurationMs = 1000;

  // ═══════════════════════════════════════════════════════
  // 内部变量 — 播放（audioplayers，参考官方 Demo）
  // ═══════════════════════════════════════════════════════

  /// 播放器 map（和官方一样，用 messageId 作为 key）
  final Map<String, AudioPlayer> _players = {};
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerPositionSubscription;
  Duration? _totalDuration;

  // ═══════════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════════

  /// 初始化录音器（在 app 启动或进入聊天页面时调用）
  Future<void> initRecorder() async {
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      // 设置录音进度回调间隔（官方用 10ms，我们用 100ms 足够）
      await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));
      _recorderInitialized = true;
      _log('录音器初始化成功');
    } catch (e) {
      _log('录音器初始化失败: $e');
      _recorderInitialized = false;
    }
  }

  /// 初始化播放器（参考官方 Demo 的 initAudioPlayer）
  void initAudioPlayer() {
    _setupSpeaker();
  }

  /// 设置播放器音频上下文（参考官方 Demo）
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
      _log('设置播放器音频上下文失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 权限管理（使用 permission_handler，参考官方 Demo）
  // ═══════════════════════════════════════════════════════

  /// 请求麦克风权限
  /// 返回 true 表示已授权
  Future<bool> requestMicrophonePermission() async {
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
    return await Permission.microphone.isGranted;
  }

  /// 检查麦克风权限是否被永久拒绝
  Future<bool> isMicrophonePermanentlyDenied() async {
    return await Permission.microphone.isPermanentlyDenied;
  }

  // ═══════════════════════════════════════════════════════
  // 录音功能（参考官方 Demo 的 record_panel.dart）
  // ═══════════════════════════════════════════════════════

  /// 开始录音
  Future<bool> startRecording() async {
    if (_state != TZAudioState.idle) {
      _log('当前状态不允许录音: $_state');
      return false;
    }

    // 确保录音器已初始化
    if (!_recorderInitialized || _recorder == null) {
      await initRecorder();
    }
    if (!_recorderInitialized || _recorder == null) {
      _log('录音器初始化失败，无法录音');
      return false;
    }

    try {
      // 获取临时目录，生成录音文件路径
      // 官方 Demo 用的是 aacADTS 格式
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/$timestamp${ext[Codec.aacADTS.index]}';

      // 开始录音（参数完全参考官方 Demo）
      await _recorder!.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        bitRate: 64000,
        numChannels: 1,
        sampleRate: 48000,
      );

      _state = TZAudioState.recording;
      _recordingSeconds = 0;
      _recordingDurationMs = 0;
      _amplitude = 0.0;

      // 监听录音进度（参考官方 Demo）
      _recorderSubscription = _recorder!.onProgress!.listen((e) {
        _recordingDurationMs = e.duration.inMilliseconds;

        // 更新振幅（flutter_sound 的 decibels 范围约 0-120）
        if (e.decibels != null) {
          _amplitude = ((e.decibels! - 30) / 70).clamp(0.0, 1.0);
        }

        // 超过最大时长自动停止
        if (e.duration.inSeconds >= maxRecordingDuration) {
          _log('录音达到最大时长，自动停止');
          // 不在这里直接 stopRecording，通过通知 UI 来处理
          _secondsTimer?.cancel();
        }
      });

      // 启动秒数计时器（用于 UI 显示）
      _secondsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        notifyListeners();

        if (_recordingSeconds >= maxRecordingDuration) {
          _secondsTimer?.cancel();
        }
      });

      notifyListeners();
      _log('开始录音: $path');
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
      _secondsTimer?.cancel();
      _cancelRecorderSubscription();

      // 停止录音，返回文件路径（参考官方 Demo）
      final filePath = await _recorder!.stopRecorder();

      _state = TZAudioState.idle;
      _amplitude = 0.0;
      notifyListeners();

      _log('stopRecorder 返回路径: $filePath, duration: $_recordingDurationMs ms');

      if (filePath == null || filePath.isEmpty) {
        _log('录音文件路径为空');
        return null;
      }

      // 检查最小时长（参考官方 Demo 的 _minLength = 1000ms）
      if (_recordingDurationMs < minRecordingDurationMs) {
        _log('录音时长不足 ${minRecordingDurationMs}ms (实际: ${_recordingDurationMs}ms)，取消发送');
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
        _log('录音文件太小，可能录音失败');
        _deleteFile(filePath);
        return null;
      }

      return RecordingResult(
        filePath: filePath,
        durationMs: _recordingDurationMs,
        fileSize: fileSize,
      );
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
      _secondsTimer?.cancel();
      _cancelRecorderSubscription();

      final filePath = await _recorder!.stopRecorder();

      // 删除录音文件
      if (filePath != null && filePath.isNotEmpty) {
        _deleteFile(filePath);
      }

      _state = TZAudioState.idle;
      _recordingSeconds = 0;
      _recordingDurationMs = 0;
      _amplitude = 0.0;
      notifyListeners();
      _log('录音已取消');
    } catch (e) {
      _log('取消录音失败: $e');
      _state = TZAudioState.idle;
      notifyListeners();
    }
  }

  /// 取消录音进度监听
  void _cancelRecorderSubscription() {
    _recorderSubscription?.cancel();
    _recorderSubscription = null;
  }

  // ═══════════════════════════════════════════════════════
  // 播放功能（参考官方 Demo 的 audio_player.dart）
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

      final id = messageId ?? 'default';

      // 清理旧的播放器（参考官方 Demo）
      _players.forEach((key, value) async {
        if (key != id) {
          await value.dispose();
        }
      });
      _players.removeWhere((key, value) => key != id);

      // 创建或复用播放器（参考官方 Demo）
      if (_players[id] == null) {
        _players[id] = AudioPlayer(playerId: id);
      }

      final player = _players[id]!;

      _log('准备播放: $source');

      _state = TZAudioState.playing;
      _playingMessageId = messageId;
      _playProgress = 0.0;
      _totalDuration = durationMs != null ? Duration(milliseconds: durationMs) : null;
      notifyListeners();

      // 监听播放状态（参考官方 Demo）
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
      _playerPositionSubscription?.cancel();
      player.onDurationChanged.listen((duration) {
        if (_totalDuration == null || _totalDuration!.inMilliseconds == 0) {
          _totalDuration = duration;
        }
      });

      // 重新监听进度
      _playerPositionSubscription = player.onPositionChanged.listen((position) {
        if (_totalDuration != null && _totalDuration!.inMilliseconds > 0) {
          _playProgress = (position.inMilliseconds / _totalDuration!.inMilliseconds).clamp(0.0, 1.0);
          notifyListeners();
        }
      });

      // 播放（参考官方 Demo：先尝试 URL，再尝试本地文件）
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

      // 停止所有播放器（参考官方 Demo 的 stopAll）
      for (var player in _players.values) {
        await player.stop();
      }
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
  // 辅助方法
  // ═══════════════════════════════════════════════════════

  /// 安全删除文件
  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log('删除文件失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 资源释放
  // ═══════════════════════════════════════════════════════

  /// 释放所有资源（参考官方 Demo 的 release）
  void releaseAll() {
    _secondsTimer?.cancel();
    _cancelRecorderSubscription();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();

    // 释放播放器
    for (var player in _players.values) {
      player.dispose();
    }
    _players.clear();

    _state = TZAudioState.idle;
    _playingMessageId = null;
    _playProgress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _secondsTimer?.cancel();
    _cancelRecorderSubscription();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();

    // 释放录音器
    try {
      _recorder?.closeRecorder();
    } catch (_) {}

    // 释放播放器
    for (var player in _players.values) {
      player.dispose();
    }
    _players.clear();

    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 日志
  // ═══════════════════════════════════════════════════════

  void _log(String msg) {
    debugPrint('[TZAudioService] $msg');
  }
}
