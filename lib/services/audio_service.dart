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
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// 终止操作回调（与官方 Demo 完全一致）
typedef StopAction = void Function();

/// 语音播放服务 — 直接复制自官方 Demo ChatAudioPlayer
class TZAudioPlayer {
  TZAudioPlayer._();

  static final TZAudioPlayer instance = TZAudioPlayer._();

  AudioContext? audioContextDefault;

  var players = <String, AudioPlayer>{};

  StopAction? _stopAction;

  StreamSubscription? _subscription;

  /// 当前正在播放的消息 ID（用于 UI 状态判断）
  String? _playingMessageId;
  String? get playingMessageId => _playingMessageId;

  void initAudioPlayer() {
    _setupSpeaker();
  }

  /// 设置播放器属性（与官方 Demo 一致）
  void _setupSpeaker() async {
    audioContextDefault = _getAudioContext();
    try {
      await AudioPlayer.global.setAudioContext(audioContextDefault!);
    } catch (e) {
      debugPrint('[TZAudioPlayer] setAudioContext 失败（桌面端可忽略）: $e');
    }
  }

  /// 获取播放器属性（与官方 Demo 一致，默认扬声器模式）
  AudioContext _getAudioContext() {
    return AudioContext(
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
  }

  /// 播放音频（与官方 Demo play 方法一致）
  Future<bool> play(
    String id,
    Source source, {
    required StopAction stopAction,
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    _setupSpeaker();
    // 回调之前的停止操作（与官方 Demo 一致）
    _stopAction?.call();

    // 构建新的播放器（与官方 Demo 一致）
    if (players[id] == null) {
      players[id] = AudioPlayer(playerId: id);
    }
    // 移除之前的播放器（与官方 Demo 一致）
    players.forEach((key, value) async {
      if (key != id) {
        await value.dispose();
      }
    });
    _subscription?.cancel();
    players.removeWhere((key, value) => key != id);
    // 使用默认的 context（与官方 Demo 一致）
    var audioContext = ctx ?? audioContextDefault;

    _stopAction = stopAction;
    _playingMessageId = id;
    var audioPlayer = players[id];
    _subscription = audioPlayer!.onPlayerStateChanged.listen((event) {
      debugPrint('[TZAudioPlayer] 播放状态: $event');
      if (event == PlayerState.stopped || event == PlayerState.completed) {
        _playingMessageId = null;
        _stopAction?.call();
        _stopAction = null;
      }
    });
    return audioPlayer
        .play(source,
            volume: volume,
            balance: balance,
            ctx: audioContext,
            position: position,
            mode: mode)
        .then((value) => true)
        .catchError((e) {
      debugPrint('[TZAudioPlayer] 播放失败: $e');
      _playingMessageId = null;
      return false;
    });
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
