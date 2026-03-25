/// 语音播放服务（直接复制自网易云信官方 Demo ChatAudioPlayer）
/// 火鹰科技出品
///
/// 播放方案 100% 复制官方 Demo（nim-uikit-flutter/nim_chatkit_ui/lib/media/audio_player.dart）：
/// - audioplayers（AudioPlayer）全平台播放
/// - 单例模式，按消息 ID 管理多个播放器
/// - 每次 play 时先 _setupSpeaker 设置音频上下文
/// - 监听 onPlayerStateChanged，completed/stopped 时回调 stopAction
///
/// 录音功能不在此文件中，直接在 chat_panel_im.dart 中使用 FlutterSoundRecorder（与官方 Demo record_panel.dart 一致）

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// 终止操作回调（与官方 Demo 完全一致）
typedef StopAction = void Function();

/// 语音播放服务 — 直接复制自官方 Demo ChatAudioPlayer
class TZAudioPlayer {
  TZAudioPlayer._();

  static final TZAudioPlayer instance = TZAudioPlayer._();

  var players = <String, AudioPlayer>{};

  StopAction? _stopAction;

  StreamSubscription? _subscription;

  /// 当前正在播放的消息 ID（用于 UI 状态判断）
  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;

  void initAudioPlayer() {
    // 设置全局音频上下文
    _setupSpeaker();
  }

  /// 设置播放器属性
  void _setupSpeaker() {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // Android: 使用 media usage，不强制 speakerphone（模拟器兼容）
        AudioPlayer.global.setAudioContext(AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.media,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gain,
            audioMode: AndroidAudioMode.normal,
            isSpeakerphoneOn: false, // 让系统自动选择输出
          ),
        ));
      } else if (!kIsWeb && Platform.isIOS) {
        AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ));
      }
    } catch (e) {
      debugPrint('[TZAudioPlayer] setAudioContext 失败: $e');
    }
  }

  /// 播放音频（与官方 Demo play 方法一致）
  Future<bool> play(
    String id,
    Source source, {
    required StopAction stopAction,
  }) async {
    _setupSpeaker();
    // 回调之前的停止操作（与官方 Demo 一致）
    _stopAction?.call();

    // 先清理旧的播放器
    for (var entry in players.entries.toList()) {
      if (entry.key != id) {
        try {
          await entry.value.stop();
          await entry.value.dispose();
        } catch (_) {}
      }
    }
    _subscription?.cancel();
    players.removeWhere((key, value) => key != id);

    // 构建新的播放器
    if (players[id] == null) {
      players[id] = AudioPlayer(playerId: id);
    }

    _stopAction = stopAction;
    _playingMessageId = id;
    var audioPlayer = players[id]!;

    // 强制设置音量为最大
    await audioPlayer.setVolume(1.0);

    // 设置播放模式为 mediaPlayer（兼容性最好，模拟器也能出声）
    await audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

    _subscription = audioPlayer.onPlayerStateChanged.listen((event) {
      debugPrint('[TZAudioPlayer] 播放状态: $event');
      if (event == PlayerState.stopped || event == PlayerState.completed) {
        _playingMessageId = null;
        _stopAction?.call();
        _stopAction = null;
      }
    });

    // 增加错误监听
    audioPlayer.onLog.listen((msg) {
      debugPrint('[TZAudioPlayer] log: $msg');
    });

    try {
      debugPrint('[TZAudioPlayer] 开始播放, source: $source');
      await audioPlayer.play(source);
      debugPrint('[TZAudioPlayer] play() 调用成功');
      return true;
    } catch (e) {
      debugPrint('[TZAudioPlayer] 播放失败: $e');
      _playingMessageId = null;
      _stopAction?.call();
      _stopAction = null;
      return false;
    }
  }

  bool isPlaying(String playerId) {
    return players[playerId]?.state == PlayerState.playing;
  }

  Future<Duration?> getCurrentPosition(String playerId) async {
    if (players[playerId]?.state == PlayerState.playing) {
      return players[playerId]!.getCurrentPosition();
    }
    return null;
  }

  void stop(String id) {
    players[id]?.stop();
    if (_playingMessageId == id) {
      _playingMessageId = null;
    }
  }

  void stopAll() {
    for (var player in players.values) {
      player.stop();
    }
    _playingMessageId = null;
    _stopAction?.call();
  }

  void release() {
    players.forEach((key, value) {
      value.dispose();
    });
    players.clear();
    _playingMessageId = null;
    _stopAction = null;
    _subscription?.cancel();
  }
}
