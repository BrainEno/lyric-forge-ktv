import '../../../project/domain/models/audio_asset.dart';

/// 播放状态
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final bool isLoading;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;
  final AudioSourceType? currentSource;
  final String? error;

  const PlaybackState({
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
    required this.isLoading,
    required this.position,
    this.duration,
    required this.bufferedPosition,
    required this.speed,
    required this.volume,
    this.currentSource,
    this.error,
  });

  /// 初始状态
  const PlaybackState.idle()
      : isPlaying = false,
        isBuffering = false,
        isCompleted = false,
        isLoading = false,
        position = Duration.zero,
        duration = null,
        bufferedPosition = Duration.zero,
        speed = 1.0,
        volume = 1.0,
        currentSource = null,
        error = null;

  /// 当前进度百分比 (0.0 - 1.0)
  double get progressPercent {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration!.inMilliseconds;
  }

  /// 缓冲进度百分比
  double get bufferedPercent {
    if (duration == null || duration!.inMilliseconds == 0) return 0.0;
    return bufferedPosition.inMilliseconds / duration!.inMilliseconds;
  }

  /// 格式化当前位置
  String get formattedPosition => _formatDuration(position);

  /// 格式化总时长
  String get formattedDuration =>
      duration != null ? _formatDuration(duration!) : '--:--';

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    AudioSourceType? currentSource,
    String? error,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      currentSource: currentSource ?? this.currentSource,
      error: error ?? this.error,
    );
  }
}
