/// 移动端录音实现 — 使用 flutter_sound（与网易云信官方 Demo 100% 一致）
/// 火鹰科技出品
///
/// 技术方案完全参考 nim-uikit-flutter 官方 Demo 的 record_panel.dart：
/// - FlutterSoundRecorder 录音
/// - Codec.aacADTS, 48000Hz, 64kbps, 单声道
/// - openRecorder() + setSubscriptionDuration(10ms)
/// - 监听 onProgress 获取录音时长
/// - stopRecorder() 返回文件路径
/// - closeRecorder() 释放资源

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 录音结果
class RecordingResult {
  final String filePath;
  final int durationMs;
  final int fileSize;

  RecordingResult({
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
  });
}

/// 与官方 Demo 一致的文件扩展名映射
const List<String> _extList = [
  '.aac', // aacADTS
  '.ogg', // opusOGG
  '.caf', // opusCAF
  '.mp3', // mp3
  '.ogg', // vorbisOGG
  '.pcm', // pcm16
  '.wav', // pcm16WAV
  '.aac', // aacMP4
  '.amr', // amrNB
  '.amr', // amrWB
  '.webm', // pcm16WEBM
  '.webm', // opusWEBM
  '.webm', // vorbisWEBM
];

/// 移动端录音器（flutter_sound）
class TZAudioRecorder {
  /// 与官方 Demo 一致：FlutterSoundRecorder
  FlutterSoundRecorder _recorderModule = FlutterSoundRecorder();

  /// 录音时长订阅（参考官方 Demo 的 _recorderSubscription）
  StreamSubscription? _recorderSubscription;

  /// 录音状态
  bool _isRecorderInited = false;
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// 录音时长（毫秒）— 来自 flutter_sound 的 onProgress
  int _recordingDurationMs = 0;
  int get recordingDurationMs => _recordingDurationMs;

  /// 录音时长（秒）— 用于 UI 显示
  int get recordingSeconds => (_recordingDurationMs / 1000).floor();

  /// 振幅（0.0 - 1.0）— 来自 flutter_sound 的 onProgress decibels
  double _amplitude = 0.0;
  double get amplitude => _amplitude;

  /// 当前录音文件路径
  String? _currentRecordingPath;

  /// 状态变更回调
  VoidCallback? onStateChanged;

  /// 最大录音时长（秒）
  static const int maxRecordingDuration = 60;

  /// 最小录音时长（毫秒）
  static const int minRecordingDurationMs = 1000;

  // ═══════════════════════════════════════════════════════
  // 初始化（参考官方 Demo initState）
  // ═══════════════════════════════════════════════════════

  /// 初始化录音器 — 与官方 Demo 的 openRecorder + setSubscriptionDuration 一致
  Future<void> init() async {
    try {
      await _recorderModule.openRecorder();

      // 与官方 Demo 一致：setSubscriptionDuration 10ms
      _recorderModule.setSubscriptionDuration(const Duration(milliseconds: 10));

      _isRecorderInited = true;
      _log('录音器初始化成功（flutter_sound）');
    } catch (e) {
      _log('录音器初始化失败: $e');
      _isRecorderInited = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // 权限（使用 permission_handler，与官方 Demo 一致）
  // ═══════════════════════════════════════════════════════

  /// 请求麦克风权限
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
  // 录音（100% 参考官方 Demo record_panel.dart）
  // ═══════════════════════════════════════════════════════

  /// 开始录音
  Future<bool> startRecording() async {
    if (_isRecording) {
      _log('已经在录音中');
      return false;
    }

    if (!_isRecorderInited) {
      _log('录音器未初始化，尝试重新初始化');
      await init();
      if (!_isRecorderInited) {
        _log('录音器初始化失败');
        return false;
      }
    }

    try {
      // 与官方 Demo 完全一致：获取临时目录 + 时间戳 + 扩展名
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final codec = Codec.aacADTS;
      final ext = _extList[codec.index];
      _currentRecordingPath = '${tempDir.path}/tz_audio_$timestamp$ext';

      _recordingDurationMs = 0;
      _amplitude = 0.0;

      // 监听录音进度（与官方 Demo 的 _recorderSubscription 一致）
      _recorderSubscription = _recorderModule.onProgress!.listen((e) {
        _recordingDurationMs = e.duration.inMilliseconds;

        // 从 decibels 计算振幅（0.0 - 1.0）
        if (e.decibels != null && e.decibels!.isFinite) {
          _amplitude = ((e.decibels! + 50) / 50).clamp(0.0, 1.0);
        }

        onStateChanged?.call();

        // 自动停止（最大 60 秒）
        if (_recordingDurationMs >= maxRecordingDuration * 1000) {
          _log('录音达到最大时长，自动停止');
        }
      });

      // 与官方 Demo 完全一致的录音参数
      await _recorderModule.startRecorder(
        toFile: _currentRecordingPath,
        codec: codec,
        bitRate: 64000,
        numChannels: 1,
        sampleRate: 48000,
      );

      _isRecording = true;
      onStateChanged?.call();
      _log('开始录音: $_currentRecordingPath (aacADTS, 48000Hz, 64kbps, mono)');
      return true;
    } catch (e) {
      _log('开始录音失败: $e');
      _isRecording = false;
      _recorderSubscription?.cancel();
      onStateChanged?.call();
      return false;
    }
  }

  /// 停止录音并返回结果
  Future<RecordingResult?> stopRecording() async {
    if (!_isRecording) {
      _log('当前不在录音状态');
      return null;
    }

    try {
      // 与官方 Demo 一致：cancelSubscriptions + stopRecorder
      _recorderSubscription?.cancel();
      _recorderSubscription = null;

      final filePath = await _recorderModule.stopRecorder();

      final durationMs = _recordingDurationMs;

      _isRecording = false;
      _amplitude = 0.0;
      onStateChanged?.call();

      _log('停止录音, 路径: $filePath, 时长: ${durationMs}ms');

      if (filePath == null || filePath.isEmpty) {
        _log('录音文件路径为空');
        return null;
      }

      // 检查最小时长
      if (durationMs < minRecordingDurationMs) {
        _log('录音时长不足 ${minRecordingDurationMs}ms (实际: ${durationMs}ms)');
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
      _isRecording = false;
      _recorderSubscription?.cancel();
      onStateChanged?.call();
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      _recorderSubscription?.cancel();
      _recorderSubscription = null;

      final filePath = await _recorderModule.stopRecorder();

      _isRecording = false;
      _recordingDurationMs = 0;
      _amplitude = 0.0;
      onStateChanged?.call();

      // 删除录音文件
      if (filePath != null && filePath.isNotEmpty) {
        _deleteFile(filePath);
      }

      _log('录音已取消');
    } catch (e) {
      _log('取消录音失败: $e');
      _isRecording = false;
      onStateChanged?.call();
    }
  }

  // ═══════════════════════════════════════════════════════
  // 资源释放（参考官方 Demo dispose）
  // ═══════════════════════════════════════════════════════

  /// 释放录音器资源
  Future<void> dispose() async {
    try {
      _recorderSubscription?.cancel();
      _recorderSubscription = null;

      if (_isRecording) {
        await _recorderModule.stopRecorder();
        _isRecording = false;
      }

      // 与官方 Demo 一致：closeRecorder
      await _recorderModule.closeRecorder();
      _isRecorderInited = false;
      _log('录音器资源已释放');
    } catch (e) {
      _log('释放录音器资源失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════════

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

  void _log(String msg) {
    debugPrint('[TZAudioRecorder] $msg');
  }
}

/// 创建移动端录音器实例
TZAudioRecorder createRecorder() => TZAudioRecorder();

/// 移动端支持录音
bool canRecord() => true;
