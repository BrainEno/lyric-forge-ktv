import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../../domain/models/playback_state.dart' as app;
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

/// Bridges LyricForge's existing playback/session state into the operating
/// system media session used by Android notifications, iOS Control Center,
/// lock-screen controls, Bluetooth/headset buttons and car integrations.
///
/// This handler deliberately does not own another audio player. System actions
/// are forwarded into [PlaybackSessionService], keeping one queue and one set
/// of shuffle/repeat semantics across the app and the OS.
class SystemMediaAudioHandler extends BaseAudioHandler with SeekHandler {
  final PlaybackSessionService session;
  final AudioPlayerService audio;

  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  StreamSubscription<app.PlaybackState>? _audioSubscription;

  PlaybackSessionState _sessionState;
  app.PlaybackState _audioState;

  SystemMediaAudioHandler({
    required this.session,
    required this.audio,
  })  : _sessionState = session.currentState,
        _audioState = audio.currentState {
    _publishSession(_sessionState);
    _publishPlayback();
    _sessionSubscription = session.stateStream.listen((state) {
      _sessionState = state;
      _publishSession(state);
      _publishPlayback();
    });
    _audioSubscription = audio.stateStream.listen((state) {
      _audioState = state;
      _publishPlayback();
    });
  }

  @override
  Future<void> play() async {
    final state = audio.currentState;
    if (state.isCompleted) {
      await session.seek(Duration.zero);
      await audio.play();
      return;
    }
    if (!state.isPlaying) {
      await session.togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    final state = audio.currentState;
    if (state.isPlaying && !state.isCompleted) {
      await session.togglePlayPause();
    }
  }

  @override
  Future<void> stop() async {
    await audio.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: audio.currentState.position,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) => session.seek(position);

  @override
  Future<void> skipToPrevious() => session.skipPrevious();

  @override
  Future<void> skipToNext() => session.skipNext();

  @override
  Future<void> skipToQueueItem(int index) => session.playAt(index);

  @override
  Future<void> playMediaItem(MediaItem item) async {
    final index = _sessionState.queue.indexWhere((entry) => entry.id == item.id);
    if (index >= 0) await session.playAt(index);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _sessionState.queue.indexWhere((entry) => entry.id == mediaId);
    if (index >= 0) await session.playAt(index);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    return session.setRepeatMode(
      switch (repeatMode) {
        AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
        AudioServiceRepeatMode.all => PlaybackRepeatMode.all,
        _ => PlaybackRepeatMode.off,
      },
    );
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    return session.setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);
  }

  Future<void> close() async {
    await _sessionSubscription?.cancel();
    await _audioSubscription?.cancel();
  }

  void _publishSession(PlaybackSessionState state) {
    final items = state.queue.map(_mediaItemFor).toList(growable: false);
    queue.add(items);
    final index = state.currentIndex;
    mediaItem.add(index >= 0 && index < items.length ? items[index] : null);
  }

  MediaItem _mediaItemFor(PlaybackItem item) {
    final artwork = item.artworkPath?.trim();
    final album = item.audioAsset.metadata['album'];
    return MediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album is String && album.trim().isNotEmpty ? album : null,
      duration: item.audioAsset.duration,
      artUri: artwork != null && artwork.isNotEmpty ? File(artwork).uri : null,
      extras: {
        'sourcePath': item.audioAsset.originalPath,
        if (item.projectId != null) 'projectId': item.projectId,
        'hasLyrics': item.hasLyrics,
      },
    );
  }

  void _publishPlayback() {
    final hasCurrent = _sessionState.currentItem != null;
    _syncRuntimeDuration();

    final controls = <MediaControl>[];
    if (hasCurrent) {
      controls.add(MediaControl.skipToPrevious);
      controls.add(
        _audioState.isPlaying && !_audioState.isCompleted
            ? MediaControl.pause
            : MediaControl.play,
      );
      if (_sessionState.canSkipNext) {
        controls.add(MediaControl.skipToNext);
      }
    }

    final processingState = _audioState.error != null
        ? AudioProcessingState.error
        : _audioState.isLoading
            ? AudioProcessingState.loading
            : _audioState.isBuffering
                ? AudioProcessingState.buffering
                : _audioState.isCompleted
                    ? AudioProcessingState.completed
                    : hasCurrent
                        ? AudioProcessingState.ready
                        : AudioProcessingState.idle;

    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: controls.isEmpty
            ? null
            : List<int>.generate(
                controls.length > 3 ? 3 : controls.length,
                (index) => index,
                growable: false,
              ),
        systemActions: hasCurrent
            ? const {
                MediaAction.seek,
                MediaAction.seekForward,
                MediaAction.seekBackward,
              }
            : const {},
        processingState: processingState,
        playing: _audioState.isPlaying && !_audioState.isCompleted,
        updatePosition: _audioState.position,
        bufferedPosition: _audioState.bufferedPosition,
        speed: _audioState.speed,
        errorMessage: _audioState.error,
        repeatMode: switch (_sessionState.repeatMode) {
          PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
          PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
          PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
        },
        shuffleMode: _sessionState.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        queueIndex: _sessionState.currentIndex >= 0
            ? _sessionState.currentIndex
            : null,
      ),
    );
  }

  void _syncRuntimeDuration() {
    final duration = _audioState.duration;
    final current = mediaItem.valueOrNull;
    if (duration == null || current == null || current.duration == duration) {
      return;
    }

    final updated = current.copyWith(duration: duration);
    mediaItem.add(updated);

    final items = queue.valueOrNull;
    final index = _sessionState.currentIndex;
    if (items == null || index < 0 || index >= items.length) return;
    final next = List<MediaItem>.of(items);
    if (next[index].id == current.id) {
      next[index] = updated;
      queue.add(List.unmodifiable(next));
    }
  }
}
