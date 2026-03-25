/// 语音录制和播放服务
/// 火鹰科技出品
///
/// 技术方案与网易云信官方 Demo（nim-uikit-flutter）100% 一致：
/// - 录音：flutter_sound（FlutterSoundRecorder）— 仅 iOS/Android
/// - 播放：audioplayers（AudioPlayer）— 全平台
/// - 权限：permission_handler — 仅 iOS/Android
///
/// 录音参数（与官方 Demo 完全一致）：
///   Codec.aacADTS, bitRate: 64000, numChannels: 1, sampleRate: 48000

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

// ═══════════════════════════════════════════════════════
// 条件导入：移动端使用 flutter_sound 录音，桌面端/Web 端使用存根
// ═══════════════════════════════════════════════════════
import 'audio_record_stub.dart'
    if (dart.library.io) 'audio_record_mobile.dart' as recorder;

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

  /// 是否支持录音（仅移动端）
  bool get canRecord => recorder.canRecord() && _isMobile;

  /// 是否是移动端（iOS/Android）
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
  int get recordingSeconds => _recorder?.recordingSeconds ?? 0;

  /// 当前录音振幅（0.0 - 1.0）
  double get amplitude => _recorder?.amplitude ?? 0.0;

  /// 当前正在播放的消息 ID
  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;

  /// 播放进度（0.0 - 1.0）
  double _playProgress = 0.0;
  double get playProgress => _playProgress;

  // ═══════════════════════════════════════════════════════
  // 内部变量 — 录音（条件导入，移动端 flutter_sound / 桌面端存根）
  // ═══════════════════════════════════════════════════════

  recorder.TZAudioRecorder? _recorder;
  bool _recorderInitialized = false;

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;
  /// 最小录音时长（毫秒）
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

  /// 初始化录音器（与官方 Demo 的 openRecorder + setSubscriptionDuration 一致）
  Future<void> initRecorder() async {
    if (!_isMobile) {
      _log('桌面端/Web 端不初始化录音器');
      return;
    }

    if (_recorderInitialized && _recorder != null) {
      _log('录音器已初始化，跳过');
      return;
    }

    try {
      _recorder = recorder.createRecorder();
      _recorder!.onStateChanged = () {
        notifyListeners();
      };
      await _recorder!.init();
      _recorderInitialized = true;
      _log('录音器初始化成功');
    } catch (e) {
      _log('录音器初始化失败: $e');
      _recorder = null;
      _recorderInitialized = false;
    }
  }

  /// 确保录音器已初始化（内部自动调用，防止 initState 中异步未完成）
  Future<bool> _ensureRecorderReady() async {
    if (!_isMobile) return false;

    if (_recorderInitialized && _recorder != null) return true;

    _log('录音器未就绪，尝试自动初始化...');
    await initRecorder();
    return _recorderInitialized && _recorder != null;
  }

  /// 初始化播放器（全平台）
  void initAudioPlayer() {
    _setupSpeaker();
  }

  /// 设置播放器音频上下文（与官方 Demo 一致）
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
  // 权限管理（使用 permission_handler，与官方 Demo 一致）
  // ═══════════════════════════════════════════════════════

  /// 请求麦克风权限
  Future<bool> requestMicrophonePermission() async {
    // 自动确保录音器已初始化
    if (!await _ensureRecorderReady()) {
      _log('录音器初始化失败，无法请求权限');
      return false;
    }
    return await _recorder!.requestMicrophonePermission();
  }

  /// 检查麦克风权限是否已授权
  Future<bool> isMicrophoneGranted() async {
    if (!await _ensureRecorderReady()) return false;
    return await _recorder!.isMicrophoneGranted();
  }

  /// 检查麦克风权限是否被永久拒绝
  Future<bool> isMicrophonePermanentlyDenied() async {
    if (!await _ensureRecorderReady()) return false;
    return await _recorder!.isMicrophonePermanentlyDenied();
  }

  // ═══════════════════════════════════════════════════════
  // 录音功能（通过条件导入，移动端使用 flutter_sound）
  // ═══════════════════════════════════════════════════════

  /// 开始录音
  Future<bool> startRecording() async {
    // 自动确保录音器已初始化
    if (!await _ensureRecorderReady()) {
      _log('录音器未就绪，无法开始录音');
      return false;
    }

    if (_state != TZAudioState.idle) {
      _log('当前状态不允许录音: $_state');
      return false;
    }

    try {
      final started = await _recorder!.startRecording();
      if (started) {
        _state = TZAudioState.recording;
        notifyListeners();
        _log('录音已开始');
      } else {
        _log('flutter_sound startRecording 返回 false');
      }
      return started;
    } catch (e) {
      _log('startRecording 异常: $e');
      return false;
    }
  }

  /// 停止录音并返回结果
  Future<recorder.RecordingResult?> stopRecording() async {
    if (_state != TZAudioState.recording || _recorder == null) {
      _log('当前不在录音状态');
      return null;
    }

    try {
      final result = await _recorder!.stopRecording();
      _state = TZAudioState.idle;
      notifyListeners();
      return result;
    } catch (e) {
      _log('stopRecording 异常: $e');
      _state = TZAudioState.idle;
      notifyListeners();
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (_state != TZAudioState.recording || _recorder == null) return;

    try {
      await _recorder!.cancelRecording();
    } catch (e) {
      _log('cancelRecording 异常: $e');
    }

    _state = TZAudioState.idle;
    notifyListeners();
    _log('录音已取消');
  }

  // ═══════════════════════════════════════════════════════
  // 播放功能（audioplayers，全平台，与官方 Demo 一致）
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
      // 先等待音频上下文设置完成
      await _setupSpeaker();

      // 每次播放创建新的 AudioPlayer 实例（与官方 Demo 一致）
      _currentPlayer?.dispose();
      _currentPlayer = AudioPlayer();

      final player = _currentPlayer!;

      _log('准备播放: $source');

      _state = TZAudioState.playing;
      _playingMessageId = messageId;
      _playProgress = 0.0;
      _totalDuration = durationMs != null ? Duration(milliseconds: durationMs) : null;
      notifyListeners();

      // 监听播放状态（与官方 Demo 的 onPlayerStateChanged 一致）
      _playerStateSubscription?.cancel();
      _playerStateSubscription = player.onPlayerStateChanged.listen((event) {
        _log('播放状态变化: $event');
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
        _log('音频时长: ${duration.inMilliseconds}ms');
        if (_totalDuration == null || _totalDuration!.inMilliseconds == 0) {
          _totalDuration = duration;
        }
      });

      // 监听播放错误
      player.onLog.listen((msg) {
        _log('AudioPlayer log: $msg');
      });

      // 播放（先尝试 URL，再尝试本地文件）
      Source audioSource;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        _log('使用 UrlSource 播放: $source');
        audioSource = UrlSource(source);
      } else {
        // 本地文件
        if (!kIsWeb) {
          final file = File(source);
          if (!await file.exists()) {
            _log('本地音频文件不存在: $source');
            _state = TZAudioState.idle;
            _playingMessageId = null;
            notifyListeners();
            return;
          }
          final fileSize = await file.length();
          _log('使用 DeviceFileSource 播放: $source (大小: $fileSize bytes)');
        }
        audioSource = DeviceFileSource(source);
      }

      await player.play(audioSource);
      _log('play() 调用成功');
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
  // 资源释放
  // ═══════════════════════════════════════════════════════

  /// 释放所有资源
  void releaseAll() {
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();

    // 释放录音器
    _recorder?.dispose();
    _recorder = null;
    _recorderInitialized = false;

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
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();

    _recorder?.dispose();
    _recorder = null;
    _recorderInitialized = false;

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
