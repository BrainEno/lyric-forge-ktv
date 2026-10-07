import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../../domain/models/playback_state.dart' as app;
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

/// Bridges Elysium Player's existing playback/session services into the
/// platform media session used by Android notifications, iOS Control Center/
/// lock screen, Bluetooth devices, headset buttons and automotive integrations.
///
/// This class deliberately does NOT own a second audio player. The existing
/// [PlaybackSessionService] remains the single queue/repeat/shuffle authority and
/// [AudioPlayerService] remains the single audio engine.
class LyricForgeSystemMediaHandler extends BaseAudioHandler {
  final PlaybackSessionService session;
  final AudioPlayerService audio;

  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  StreamSubscription<app.PlaybackState>? _playbackSubscription;

  PlaybackSessionState _sessionState;
  app.PlaybackState _audioState;
  String? _lastMediaId;
  Duration? _lastPublishedDuration;

  LyricForgeSystemMediaHandler({
    required this.session,
    required this.audio,
  })  : _sessionState = session.currentState,
        _audioState = audio.currentState {
    _publishSession(_sessionState);
    _publishPlayback(_audioState);

    _sessionSubscription = session.stateStream.listen(_publishSession);
    _playbackSubscription = audio.stateStream.listen(_publishPlayback);
  }

  void _publishSession(PlaybackSessionState state) {
    _sessionState = state;

    final systemQueue = state.queue.map(_toMediaItem).toList(growable: false);
    queue.add(systemQueue);

    final current = state.currentItem;
    if (current == null) {
      _lastMediaId = null;
      _lastPublishedDuration = null;
      mediaItem.add(null);
    } else {
      final duration = _durationFor(current);
      _lastMediaId = current.id;
      _lastPublishedDuration = duration;
      mediaItem.add(_toMediaItem(current, duration: duration));
    }

    _broadcastPlaybackState();
  }

  void _publishPlayback(app.PlaybackState state) {
    _audioState = state;

    final current = _sessionState.currentItem;
    final duration = state.duration;
    if (current != null &&
        duration != null &&
        (_lastMediaId != current.id || _lastPublishedDuration != duration)) {
      _lastMediaId = current.id;
      _lastPublishedDuration = duration;
      mediaItem.add(_toMediaItem(current, duration: duration));
    }

    _broadcastPlaybackState();
  }

  void _broadcastPlaybackState() {
    final current = _sessionState.currentItem;
    final controls = <MediaControl>[];

    if (current != null) {
      if (_sessionState.canSkipPrevious) {
        controls.add(MediaControl.skipToPrevious);
      }
      controls.add(
        _audioState.isPlaying ? MediaControl.pause : MediaControl.play,
      );
      if (_sessionState.canSkipNext) {
        controls.add(MediaControl.skipToNext);
      }
    }

    final compactIndices = <int>[
      for (var i = 0; i < controls.length && i < 3; i++) i,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: compactIndices,
        systemActions: current == null
            ? const {}
            : const {
                MediaAction.seek,
                MediaAction.setRepeatMode,
                MediaAction.setShuffleMode,
                MediaAction.setSpeed,
              },
        processingState: _processingState(current != null),
        playing: _audioState.isPlaying,
        updatePosition: _audioState.position,
        bufferedPosition: _audioState.bufferedPosition,
        speed: _audioState.speed,
        errorCode: _audioState.error == null ? null : 1,
        errorMessage: _audioState.error,
        repeatMode: switch (_sessionState.repeatMode) {
          PlaybackRepeatMode.off => AudioServiceRepeatMode.none,
          PlaybackRepeatMode.one => AudioServiceRepeatMode.one,
          PlaybackRepeatMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: _sessionState.shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        queueIndex: current == null ? null : _sessionState.currentIndex,
      ),
    );
  }

  AudioProcessingState _processingState(bool hasCurrentItem) {
    if (_audioState.error != null) return AudioProcessingState.error;
    if (!hasCurrentItem) return AudioProcessingState.idle;
    if (_audioState.isLoading) return AudioProcessingState.loading;
    if (_audioState.isBuffering) return AudioProcessingState.buffering;
    if (_audioState.isCompleted) return AudioProcessingState.completed;
    return AudioProcessingState.ready;
  }

  Uri? _artUriFor(PlaybackItem item) {
    final localArtwork = item.artworkPath?.trim();
    if (localArtwork != null && localArtwork.isNotEmpty) {
      // Preserve the previous local-track behaviour: platform media sessions may
      // receive the URI before the file is observed by this isolate. For remote
      // streams, however, a deleted cache file should fall back to the protected
      // Media Hub artwork URL instead of publishing a dead file URI.
      if (!item.isRemoteStream || File(localArtwork).existsSync()) {
        return Uri.file(localArtwork);
      }
    }

    final rawRemoteArtwork = item.audioAsset.metadata['remoteArtworkUri'];
    if (rawRemoteArtwork is! String || rawRemoteArtwork.trim().isEmpty) {
      return null;
    }
    final remote = Uri.tryParse(rawRemoteArtwork.trim());
    if (remote == null ||
        (remote.scheme != 'http' && remote.scheme != 'https')) {
      return null;
    }
    return remote;
  }

  MediaItem _toMediaItem(
    PlaybackItem item, {
    Duration? duration,
  }) {
    final rawAlbum = item.audioAsset.metadata['album'];
    final album = rawAlbum is String && rawAlbum.trim().isNotEmpty
        ? rawAlbum.trim()
        : null;

    return MediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album,
      duration: duration ?? item.audioAsset.duration,
      artUri: _artUriFor(item),
      playable: true,
      extras: {
        if (item.streamUri != null) 'streamUri': item.streamUri.toString(),
        if (item.streamUri == null) 'sourcePath': item.audioAsset.originalPath,
        'hasLyrics': item.hasLyrics,
        if (item.projectId != null) 'projectId': item.projectId!,
      },
    );
  }

  Duration? _durationFor(PlaybackItem item) {
    if (_sessionState.currentItem?.id == item.id && _audioState.duration != null) {
      return _audioState.duration;
    }
    return item.audioAsset.duration;
  }

  @override
  Future<void> play() async {
    if (_sessionState.currentItem == null || _audioState.isPlaying) return;
    await session.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    if (!_audioState.isPlaying) return;
    await session.togglePlayPause();
  }

  @override
  Future<void> stop() => session.clearQueue(keepCurrent: false);

  @override
  Future<void> seek(Duration position) => session.seek(position);

  @override
  Future<void> skipToPrevious() => session.skipPrevious();

  @override
  Future<void> skipToNext() => session.skipNext();

  @override
  Future<void> skipToQueueItem(int index) => session.playAt(index);

  @override
  Future<void> playMediaItem(MediaItem item) => playFromMediaId(item.id);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _sessionState.queue.indexWhere((item) => item.id == mediaId);
    if (index < 0) return;
    if (index == _sessionState.currentIndex) {
      await play();
      return;
    }
    await session.playAt(index);
  }

  @override
  Future<void> fastForward() => _seekRelative(const Duration(seconds: 10));

  @override
  Future<void> rewind() => _seekRelative(const Duration(seconds: -10));

  Future<void> _seekRelative(Duration delta) async {
    final target = _audioState.position + delta;
    final duration = _audioState.duration;
    var safe = target < Duration.zero ? Duration.zero : target;
    if (duration != null && safe > duration) safe = duration;
    await session.seek(safe);
  }

  @override
  Future<void> setSpeed(double speed) => audio.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) {
    return session.setRepeatMode(
      switch (repeatMode) {
        AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
        AudioServiceRepeatMode.all => PlaybackRepeatMode.all,
        AudioServiceRepeatMode.none || AudioServiceRepeatMode.group =>
          PlaybackRepeatMode.off,
      },
    );
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) {
    return session.setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);
  }

  Future<void> disposeBridge() async {
    await _sessionSubscription?.cancel();
    await _playbackSubscription?.cancel();
  }
}
