/// 语音录制和播放服务
/// 火鹰科技出品
///
/// 职责：
/// 1. 录制语音消息（使用 record 包，全平台支持）
/// 2. 播放语音消息（使用 just_audio 包，全平台支持）
/// 3. 管理录音和播放状态
/// 4. 安卓权限管理（录音权限检测与引导）
///
/// 关键设计：
/// - AudioRecorder 每次录音创建新实例，录音结束后 dispose（官方推荐用法）
/// - AudioPlayer 每次播放前重新创建，避免安卓上播放器状态异常
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
  final int fileSize; // 文件大小（字节）

  RecordingResult({
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
  });
}

/// 语音服务状态
enum TZAudioState {
  idle,       // 空闲
  recording,  // 录音中
  playing,    // 播放中
}

/// 权限状态
enum TZAudioPermissionStatus {
  granted,          // 已授权
  denied,           // 被拒绝（可再次请求）
  permanentlyDenied, // 永久拒绝（需要去设置页面）
  unknown,          // 未知
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

  /// 最后一次权限检查结果
  TZAudioPermissionStatus _lastPermissionStatus = TZAudioPermissionStatus.unknown;
  TZAudioPermissionStatus get lastPermissionStatus => _lastPermissionStatus;

  /// 权限请求次数（用于判断是否永久拒绝）
  int _permissionRequestCount = 0;

  // ═══════════════════════════════════════════════════════
  // 内部变量
  // ═══════════════════════════════════════════════════════

  /// 当前录音器实例（每次录音创建新实例，录音结束后 dispose）
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  Timer? _recordingTimer;
  Timer? _amplitudeTimer;
  DateTime? _recordingStartTime;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerPositionSubscription;
  Duration? _totalDuration;
  String? _currentRecordingPath;

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;

  /// 最小录音时长（秒），低于此时长不发送
  static const int minRecordingDuration = 1;

  /// 最小有效文件大小（字节），低于此大小认为录音失败
  static const int minValidFileSize = 1024; // 1KB

  // ═══════════════════════════════════════════════════════
  // 权限管理
  // ═══════════════════════════════════════════════════════

  /// 检查麦克风权限
  /// 返回权限状态，调用者根据状态决定是否引导用户去设置页面
  Future<TZAudioPermissionStatus> checkPermission() async {
    try {
      // 用临时实例检查权限，检查完立即 dispose
      final tempRecorder = AudioRecorder();
      final hasPermission = await tempRecorder.hasPermission();
      await tempRecorder.dispose();

      if (hasPermission) {
        _lastPermissionStatus = TZAudioPermissionStatus.granted;
        _permissionRequestCount = 0;
        _log('麦克风权限已授予');
      } else {
        _permissionRequestCount++;
        if (_permissionRequestCount >= 2) {
          _lastPermissionStatus = TZAudioPermissionStatus.permanentlyDenied;
          _log('麦克风权限被永久拒绝（请求次数: $_permissionRequestCount）');
        } else {
          _lastPermissionStatus = TZAudioPermissionStatus.denied;
          _log('麦克风权限被拒绝（请求次数: $_permissionRequestCount）');
        }
      }

      return _lastPermissionStatus;
    } catch (e) {
      _log('检查权限异常: $e');
      _lastPermissionStatus = TZAudioPermissionStatus.unknown;
      return TZAudioPermissionStatus.unknown;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 录音功能
  // ═══════════════════════════════════════════════════════

  /// 开始录音
  /// 返回值：
  /// - true: 录音成功开始
  /// - false: 录音失败（权限问题或其他错误）
  Future<bool> startRecording() async {
    if (_state != TZAudioState.idle) {
      _log('当前状态不允许录音: $_state');
      return false;
    }

    try {
      // ═══ 关键修复：每次录音创建全新的 AudioRecorder 实例 ═══
      // 安卓上复用旧的 AudioRecorder 实例可能导致录音无声
      // 官方示例也是每次 new AudioRecorder()
      await _disposeRecorder();
      _recorder = AudioRecorder();

      // 检查权限（直接用新创建的 recorder 检查）
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        _permissionRequestCount++;
        if (_permissionRequestCount >= 2) {
          _lastPermissionStatus = TZAudioPermissionStatus.permanentlyDenied;
        } else {
          _lastPermissionStatus = TZAudioPermissionStatus.denied;
        }
        _log('没有麦克风权限，状态: $_lastPermissionStatus');
        // 权限检查失败，dispose 掉刚创建的 recorder
        await _disposeRecorder();
        return false;
      }
      _lastPermissionStatus = TZAudioPermissionStatus.granted;
      _permissionRequestCount = 0;

      // 获取临时目录
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = p.join(dir.path, 'voice_$timestamp.m4a');

      // 配置录音参数
      // 使用标准 44100Hz 采样率 + 128kbps 码率，兼容性最好
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1, // 单声道，语音消息足够
      );

      // 开始录音
      _log('准备开始录音: $_currentRecordingPath');
      await _recorder!.start(config, path: _currentRecordingPath!);

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
          _recordingTimer?.cancel();
        }
      });

      // 启动振幅检测（降低频率到 300ms，且仅在变化超过阈值时通知 UI，
      // 避免 iOS 上因高频 notifyListeners 导致计时器显示跳动）
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
        if (_recorder == null) return;
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
      _log('开始录音成功: $_currentRecordingPath');
      return true;
    } catch (e) {
      _log('开始录音失败: $e');
      _state = TZAudioState.idle;
      _currentRecordingPath = null;
      await _disposeRecorder();
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

      // ═══ 关键：录音结束后立即 dispose recorder ═══
      await _disposeRecorder();

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
        _deleteFile(filePath);
        return null;
      }

      // 验证录音文件大小
      final file = File(filePath);
      if (!await file.exists()) {
        _log('录音文件不存在: $filePath');
        return null;
      }

      final fileSize = await file.length();
      _log('录音文件大小: $fileSize bytes, 时长: ${durationMs}ms');

      if (fileSize < minValidFileSize) {
        _log('录音文件太小 ($fileSize bytes < $minValidFileSize bytes)，可能录音失败');
        _deleteFile(filePath);
        return null;
      }

      _log('录音完成: $filePath, 时长: ${durationMs}ms, 大小: ${fileSize}bytes');
      return RecordingResult(
        filePath: filePath,
        durationMs: durationMs,
        fileSize: fileSize,
      );
    } catch (e) {
      _log('停止录音失败: $e');
      _state = TZAudioState.idle;
      await _disposeRecorder();
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
        _deleteFile(filePath);
      }

      // dispose recorder
      await _disposeRecorder();

      _state = TZAudioState.idle;
      _recordingSeconds = 0;
      _amplitude = 0.0;
      _currentRecordingPath = null;
      notifyListeners();
      _log('录音已取消');
    } catch (e) {
      _log('取消录音失败: $e');
      _state = TZAudioState.idle;
      await _disposeRecorder();
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
      // 每次播放前重新创建 AudioPlayer
      await _disposePlayer();
      _player = AudioPlayer();

      _log('准备播放: $source');

      // 设置音频源
      Duration? duration;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        duration = await _player!.setUrl(source);
      } else {
        // 本地文件播放前检查文件是否存在
        final file = File(source);
        if (!await file.exists()) {
          _log('本地音频文件不存在: $source');
          return;
        }
        final fileSize = await file.length();
        _log('本地音频文件大小: $fileSize bytes');
        if (fileSize < minValidFileSize) {
          _log('音频文件太小，可能是空文件');
          return;
        }
        duration = await _player!.setFilePath(source);
      }

      _state = TZAudioState.playing;
      _playingMessageId = messageId;
      _playProgress = 0.0;
      _totalDuration = duration ?? _player!.duration;
      notifyListeners();

      _log('音频时长: ${_totalDuration?.inMilliseconds}ms');

      // 监听播放状态
      _playerStateSubscription?.cancel();
      _playerStateSubscription = _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onPlaybackCompleted();
        }
      }, onError: (error) {
        _log('播放流错误: $error');
        _onPlaybackCompleted();
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

  /// 安全释放录音器
  Future<void> _disposeRecorder() async {
    try {
      await _recorder?.dispose();
    } catch (e) {
      _log('释放录音器异常: $e');
    }
    _recorder = null;
  }

  /// 释放播放器资源
  Future<void> _disposePlayer() async {
    try {
      _playerStateSubscription?.cancel();
      _playerPositionSubscription?.cancel();
      _playerStateSubscription = null;
      _playerPositionSubscription = null;
      await _player?.dispose();
      _player = null;
    } catch (e) {
      _log('释放播放器异常: $e');
      _player = null;
    }
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
