import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../domain/models/audio_preview_state.dart';
import '../../domain/services/audio_preview_service.dart';
import 'desktop_audio_backend.dart';

/// `just_audio` implementation of the audition channel.
///
/// Runs on the same desktop backend as the app player ([initializeDesktopAudioBackend])
/// so a take encoded by FFmpeg decodes identically to the song it was recorded
/// over. The backend registration is idempotent, so constructing this after the
/// main player is safe and constructing it first registers the backend for both.
class JustAudioAudioPreviewService implements AudioPreviewService {
  JustAudioAudioPreviewService() {
    initializeDesktopAudioBackend();
    _player = AudioPlayer();
    _bind();
  }

  late final AudioPlayer _player;
  final StreamController<AudioPreviewState> _controller =
      StreamController<AudioPreviewState>.broadcast();
  AudioPreviewState _state = const AudioPreviewState.idle();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void _bind() {
    _subscriptions.add(
      _player.positionStream.listen((position) {
        _emit(_state.copyWith(position: position));
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((duration) {
        if (duration == null) return;
        _emit(_state.copyWith(duration: duration));
      }),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        final completed =
            playerState.processingState == ProcessingState.completed;
        _emit(_state.copyWith(isPlaying: playerState.playing && !completed));
      }),
    );
    _subscriptions.add(
      _player.errorStream.listen((_) {
        _emit(_state.copyWith(isPlaying: false));
      }),
    );
  }

  void _emit(AudioPreviewState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  AudioPreviewState get currentState => _state;

  @override
  Stream<AudioPreviewState> get stateStream => _controller.stream;

  @override
  Future<Duration?> loadFile(String path) async {
    await _player.stop();
    _emit(
      _state.copyWith(
        isLoaded: false,
        isPlaying: false,
        position: Duration.zero,
        clearDuration: true,
      ),
    );
    final duration = await _player.setFilePath(path);
    _emit(
      _state.copyWith(
        isLoaded: true,
        isPlaying: false,
        position: Duration.zero,
        duration: duration,
      ),
    );
    return duration;
  }

  @override
  Future<void> play() async {
    // just_audio completes this future when playback ends, not when it starts,
    // so awaiting it here would hang the caller for the length of the take.
    unawaited(_player.play());
    _emit(_state.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emit(_state.copyWith(isPlaying: false));
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero);
    _emit(_state.copyWith(isPlaying: false, position: Duration.zero));
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();
    await _controller.close();
  }
}
