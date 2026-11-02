/// State of the app-scoped audition channel.
///
/// Deliberately smaller than [PlaybackState]: an audition plays one loose file
/// (a KTV take, an exported mix) and never owns a queue, a source switch or a
/// speed. Keeping it separate is what stops an audition from being mistaken for
/// "the song that is playing".
class AudioPreviewState {
  /// True once a file has been loaded and can be played or seeked.
  final bool isLoaded;
  final bool isPlaying;
  final Duration position;

  /// Null until the player reports the file's real duration.
  final Duration? duration;

  const AudioPreviewState({
    required this.isLoaded,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });

  const AudioPreviewState.idle()
    : isLoaded = false,
      isPlaying = false,
      position = Duration.zero,
      duration = null;

  AudioPreviewState copyWith({
    bool? isLoaded,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
  }) {
    return AudioPreviewState(
      isLoaded: isLoaded ?? this.isLoaded,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: clearDuration ? null : duration ?? this.duration,
    );
  }
}
