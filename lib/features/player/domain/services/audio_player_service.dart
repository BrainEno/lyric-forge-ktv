import 'dart:async';

import '../../../project/domain/models/audio_asset.dart';
import '../models/playback_state.dart';

/// 音频播放器服务接口
abstract class AudioPlayerService {
  /// 加载工程音频
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  });

  /// 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// 切换音源
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
