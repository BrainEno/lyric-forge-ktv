import 'dart:async';

import 'package:audio_service/audio_service.dart' as system_audio;

import '../../domain/models/playback_state.dart' as app_audio;
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

/// Bridges LyricForge's existing playback/session state to the operating
/// system's media session without creating a second playback state machine.
///
/// The app's [PlaybackSessionService] remains authoritative for queue order,
/// shuffle/repeat semantics and previous/next behaviour. System controls from
/// lock screens, notifications, headsets and car integrations are forwarded
/// back into that same service.
class SystemMediaControlsHandler extends system_audio.BaseAudioHandler
    with system_audio.SeekHandler {
  final PlaybackSessionService _session;
  final AudioPlayerService _audioPlayer;

  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  StreamSubscription<app_audio.PlaybackState>? _playbackSubscription;
  PlaybackSessionState _sessionState;
  app_audio.PlaybackState _appPlaybackState;
  Duration? _publishedDuration;
  bool _systemStopped = false;
  String? _lastCurrentItemId;

  SystemMediaControlsHandler({
    required PlaybackSessionService session,
    required AudioPlayerService audioPlayer,
  })  : _session = session,
        _audioPlayer = audioPlayer,
        _sessionState = session.currentState,
        _appPlaybackState = audioPlayer.currentState,
        _lastCurrentItemId = session.currentState.currentItem?.id {
    _publishQueueAndItem();
    _publishPlaybackState();

    _sessionSubscription = _session.stateStream.listen((state) {
      final nextId = state.currentItem?.id;
      if (nextId != _lastCurrentItemId) {
        _systemStopped = false;
        _lastCurrentItemId = nextId;
      }
      _sessionState = state;
      _publishedDuration = null;
      _publishQueueAndItem();
      _publishPlaybackState();
    });
    _playbackSubscription = _audioPlayer.stateStream.listen((state) {
      _appPlaybackState = state;
      _publishCurrentDurationIfNeeded();
      _publishPlaybackState();
    });
  }

  @override
  Future<void> play() async {
    final current = _sessionState.currentItem;
    if (current == null) return;
    _systemStopped = false;
    if (_appPlaybackState.isCompleted) {
      await _session.seek(Duration.zero);
    }
    await _audioPlayer.play();
    _publishPlaybackState();
  }

  @override
  Future<void> pause() => _audioPlayer.pause();

  @override
  Future<void> stop() async {
    _systemStopped = true;
    await _audioPlayer.stop();
    _appPlaybackState = _audioPlayer.currentState;
    _publishPlaybackState();
  }

  @override
  Future<void> seek(Duration position) => _session.seek(position);

  @override
  Future<void> skipToNext() => _session.skipNext();

  @override
  Future<void> skipToPrevious() => _session.skipPrevious();

  @override
  Future<void> skipToQueueItem(int index) => _session.playAt(index);

  @override
  Future<void> click([
    system_audio.MediaButton button = system_audio.MediaButton.media,
  ]) async {
    switch (button) {
      case system_audio.MediaButton.next:
        await skipToNext();
        return;
      case system_audio.MediaButton.previous:
        await skipToPrevious();
        return;
      case system_audio.MediaButton.media:
        if (_appPlaybackState.isPlaying && !_systemStopped) {
          await pause();
        } else {
          await play();
        }
        return;
    }
  }

  @override
  Future<void> setRepeatMode(system_audio.AudioServiceRepeatMode repeatMode) {
    final mode = switch (repeatMode) {
      system_audio.AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      system_audio.AudioServiceRepeatMode.all ||
      system_audio.AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
      _ => PlaybackRepeatMode.off,
    };
    return _session.setRepeatMode(mode);
  }

  @override
  Future<void> setShuffleMode(system_audio.AudioServiceShuffleMode shuffleMode) {
    return _session.setShuffleEnabled(
      shuffleMode != system_audio.AudioServiceShuffleMode.none,
    );
  }

  /// Android may remove the Flutter activity from recents while the foreground
  /// media service keeps running. Do not stop playback here.
  @override
  Future<void> onTaskRemoved() async {}

  Future<void> disposeBridge() async {
    await _sessionSubscription?.cancel();
    await _playbackSubscription?.cancel();
  }

  void _publishQueueAndItem() {
    final items = _sessionState.queue.map(_toSystemItem).toList(growable: false);
    queue.add(items);

    final current = _sessionState.currentItem;
    mediaItem.add(
      current == null
          ? null
          : _toSystemItem(
              current,
              duration: _appPlaybackState.duration ?? current.audioAsset.duration,
            ),
    );
  }

  void _publishCurrentDurationIfNeeded() {
    final current = _sessionState.currentItem;
    final duration = _appPlaybackState.duration;
    if (current == null || duration == null || duration == _publishedDuration) {
      return;
    }
    _publishedDuration = duration;
    mediaItem.add(_toSystemItem(current, duration: duration));
  }

  system_audio.MediaItem _toSystemItem(
    PlaybackItem item, {
    Duration? duration,
  }) {
    final rawAlbum = item.audioAsset.metadata['album'];
    final album = rawAlbum is String && rawAlbum.trim().isNotEmpty
        ? rawAlbum.trim()
        : null;
    final artwork = item.artworkPath?.trim();

    return system_audio.MediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album,
      duration: duration ?? item.audioAsset.duration,
      artUri: artwork == null || artwork.isEmpty ? null : _artUri(artwork),
      extras: {
        'sourcePath': item.audioAsset.originalPath,
        if (item.projectId != null) 'projectId': item.projectId,
        'hasLyrics': item.hasLyrics,
      },
    );
  }

  Uri _artUri(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(value);
  }

  void _publishPlaybackState() {
    final current = _sessionState.currentItem;
    final stopped = _systemStopped;
    final playing = !stopped && _appPlaybackState.isPlaying;
    final controls = <system_audio.MediaControl>[
      if (current != null && _sessionState.canSkipPrevious)
        system_audio.MediaControl.skipToPrevious,
      if (playing)
        system_audio.MediaControl.pause
      else if (current != null)
        system_audio.MediaControl.play,
      if (current != null && _sessionState.canSkipNext)
        system_audio.MediaControl.skipToNext,
    ];

    playbackState.add(
      system_audio.PlaybackState(
        controls: controls,
        androidCompactActionIndices: [
          for (var i = 0; i < controls.length && i < 3; i++) i,
        ],
        systemActions: current == null || stopped
            ? const <system_audio.MediaAction>{}
            : const {
                system_audio.MediaAction.seek,
                system_audio.MediaAction.seekForward,
                system_audio.MediaAction.seekBackward,
              },
        processingState: _processingState(),
        playing: playing,
        updatePosition: _appPlaybackState.position,
        bufferedPosition: _appPlaybackState.bufferedPosition,
        speed: _appPlaybackState.speed,
        queueIndex: current == null ? null : _sessionState.currentIndex,
        repeatMode: switch (_sessionState.repeatMode) {
          PlaybackRepeatMode.off => system_audio.AudioServiceRepeatMode.none,
          PlaybackRepeatMode.all => system_audio.AudioServiceRepeatMode.all,
          PlaybackRepeatMode.one => system_audio.AudioServiceRepeatMode.one,
        },
        shuffleMode: _sessionState.shuffleEnabled
            ? system_audio.AudioServiceShuffleMode.all
            : system_audio.AudioServiceShuffleMode.none,
        errorMessage: _appPlaybackState.error,
      ),
    );
  }

  system_audio.AudioProcessingState _processingState() {
    if (_systemStopped || _sessionState.currentItem == null) {
      return system_audio.AudioProcessingState.idle;
    }
    if (_appPlaybackState.error != null) {
      return system_audio.AudioProcessingState.error;
    }
    if (_appPlaybackState.isLoading) {
      return system_audio.AudioProcessingState.loading;
    }
    if (_appPlaybackState.isBuffering) {
      return system_audio.AudioProcessingState.buffering;
    }
    if (_appPlaybackState.isCompleted) {
      return system_audio.AudioProcessingState.completed;
    }
    return system_audio.AudioProcessingState.ready;
  }
}
