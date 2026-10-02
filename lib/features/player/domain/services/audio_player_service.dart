import 'dart:async';

import '../../../project/domain/models/audio_asset.dart';
import '../models/playback_state.dart';

/// 音频播放器服务接口
abstract class AudioPlayerService {
  /// 加载工程内的本地音频
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  });

  /// 加载远程或其他 URI 音频。
  ///
  /// Media Hub 手机端通过此入口播放桌面端音频，避免 presentation 层
  /// 直接依赖 just_audio 或 HTTP 实现。
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  });

  /// 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// 切换工程音源
  Future<void> switchSource(AudioSourceType source);

  /// 播放参数
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);

  /// 状态流
  Stream<PlaybackState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// 当前状态
  PlaybackState get currentState;

  /// 释放资源
  Future<void> dispose();
}
