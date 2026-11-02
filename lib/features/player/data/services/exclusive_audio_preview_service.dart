import 'dart:async';

import '../../domain/models/audio_preview_state.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_preview_service.dart';
import '../../domain/services/audio_player_service.dart';

/// Keeps the audition channel and the app player from sounding at the same
/// time.
///
/// Before this existed the KTV take sheet built its own `AudioPlayer`, and
/// nothing paused the song before previewing a take: stopping a recording leaves
/// playback running, so pressing "播放原始人声" played the take *over* the song,
/// at a different position, with two progress bars disagreeing.
///
/// Both directions are enforced here rather than in the widget, because the
/// widget can disappear mid-flight (sheet dismissed, route popped) and the
/// invariant has to hold regardless:
///
///  * starting an audition pauses the song first;
///  * as soon as the song starts playing again, the audition pauses.
class ExclusiveAudioPreviewService implements AudioPreviewService {
  ExclusiveAudioPreviewService({
    required AudioPreviewService delegate,
    required AudioPlayerService primaryPlayer,
  }) : _delegate = delegate,
       _primaryPlayer = primaryPlayer {
    _primaryStateSubscription = primaryPlayer.stateStream.listen((state) {
      if (!state.isPlaying) return;
      if (!_delegate.currentState.isPlaying) return;
      unawaited(_delegate.pause());
    });
  }

  final AudioPreviewService _delegate;
  final AudioPlayerService _primaryPlayer;
  late final StreamSubscription<PlaybackState> _primaryStateSubscription;

  @override
  Stream<AudioPreviewState> get stateStream => _delegate.stateStream;

  @override
  AudioPreviewState get currentState => _delegate.currentState;

  @override
  Future<Duration?> loadFile(String path) => _delegate.loadFile(path);

  @override
  Future<void> play() async {
    if (_primaryPlayer.currentState.isPlaying) {
      await _primaryPlayer.pause();
    }
    await _delegate.play();
  }

  @override
  Future<void> pause() => _delegate.pause();

  @override
  Future<void> stop() => _delegate.stop();

  @override
  Future<void> seek(Duration position) => _delegate.seek(position);

  @override
  Future<void> dispose() async {
    await _primaryStateSubscription.cancel();
    await _delegate.dispose();
  }
}
