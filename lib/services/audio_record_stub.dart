/// 桌面端/Web 端录音存根 — 不引入 flutter_sound
/// 火鹰科技出品
///
/// flutter_sound 不支持 macOS/Windows 桌面端，
/// 因此桌面端和 Web 端使用此存根文件，所有录音操作返回不支持。
/// 播放功能由 audioplayers 提供（全平台支持），不受影响。

import 'package:flutter/foundation.dart';

/// 录音结果（与移动端保持相同接口）
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

/// 桌面端/Web 端录音器存根
class TZAudioRecorder {
  bool get isRecording => false;
  int get recordingDurationMs => 0;
  int get recordingSeconds => 0;
  double get amplitude => 0.0;

  VoidCallback? onStateChanged;

  Future<void> init() async {
    debugPrint('[TZAudioRecorder] 桌面端/Web 端不支持录音（flutter_sound 仅支持移动端）');
  }

  Future<bool> requestMicrophonePermission() async => false;
  Future<bool> isMicrophoneGranted() async => false;
  Future<bool> isMicrophonePermanentlyDenied() async => false;

  Future<bool> startRecording() async {
    debugPrint('[TZAudioRecorder] 桌面端/Web 端不支持录音');
    return false;
  }

  Future<RecordingResult?> stopRecording() async => null;
  Future<void> cancelRecording() async {}
  Future<void> dispose() async {}
}

/// 创建桌面端/Web 端录音器存根
TZAudioRecorder createRecorder() => TZAudioRecorder();

/// 桌面端/Web 端不支持录音
bool canRecord() => false;
