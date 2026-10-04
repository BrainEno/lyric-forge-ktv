import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/playback_state.dart' as app_state;
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

Future<void> initializeSystemMediaSession({
  required PlaybackSessionService playbackSession,
  required AudioPlayerService audioPlayer,
}) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());

    await audio_service.AudioService.init(
      builder: () => PlaybackSessionAudioHandler(
        playbackSession: playbackSession,
        audioPlayer: audioPlayer,
      ),
      config: const audio_service.AudioServiceConfig(
        androidNotificationChannelId: 'com.lyricforge.ktv.playback',
        androidNotificationChannelName: 'LyricForge 音乐播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    ).timeout(const Duration(seconds: 10));
  } catch (error, stackTrace) {
    // System media integration must never prevent the local player from
    // starting. Playback still works in-app if a platform media service fails.
    debugPrint('System media session unavailable: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class PlaybackSessionAudioHandler extends audio_service.BaseAudioHandler {
  final PlaybackSessionService _session;
  final AudioPlayerService _audio;

  late PlaybackSessionState _sessionState;
  late app_state.PlaybackState _playerState;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  StreamSubscription<app_state.PlaybackState>? _playerSubscription;

  PlaybackSessionAudioHandler({
    required PlaybackSessionService playbackSession,
    required AudioPlayerService audioPlayer,
  })  : _session = playbackSession,
        _audio = audioPlayer {
    _sessionState = _session.currentState;
    _playerState = _audio.currentState;

    _publishSession(_sessionState);
    _publishPlayback(_playerState);

    _sessionSubscription = _session.stateStream.listen(_publishSession);
    _playerSubscription = _audio.stateStream.listen(_publishPlayback);
  }

  void _publishSession(PlaybackSessionState state) {
    _sessionState = state;
    queue.add(
      List<audio_service.MediaItem>.unmodifiable(
        state.queue.map(_mediaItemFor),
      ),
    );

    final current = state.currentItem;
    mediaItem.add(
      current == null
          ? null
          : _mediaItemFor(
              current,
              durationOverride: _playerState.duration,
            ),
    );
    _publishPlayback(_playerState);
  }

  void _publishPlayback(app_state.PlaybackState state) {
    _playerState = state;
    final current = _sessionState.currentItem;
    if (current != null) {
      mediaItem.add(
        _mediaItemFor(
          current,
          durationOverride: state.duration,
        ),
      );
    }

    final shouldShowPause = state.isPlaying && !state.isCompleted;
    final controls = current == null
        ? const <audio_service.MediaControl>[]
        : <audio_service.MediaControl>[
            if (_sessionState.canSkipPrevious)
              audio_service.MediaControl.skipToPrevious,
            shouldShowPause
                ? audio_service.MediaControl.pause
                : audio_service.MediaControl.play,
            if (_sessionState.canSkipNext)
              audio_service.MediaControl.skipToNext,
          ];

    playbackState.add(
      audio_service.PlaybackState(
        controls: controls,
        androidCompactActionIndices: [
          for (var index = 0; index < controls.length && index < 3; index++)
            index,
        ],
        systemActions: current == null
            ? const <audio_service.MediaAction>{}
            : const {audio_service.MediaAction.seek},
        processingState: _processingState(state),
        playing: current != null && shouldShowPause,
        updatePosition: state.position,
        bufferedPosition: state.bufferedPosition,
        speed: state.speed,
        queueIndex:
            _sessionState.currentIndex >= 0 ? _sessionState.currentIndex : null,
        repeatMode: _repeatMode(_sessionState.repeatMode),
        shuffleMode: _sessionState.shuffleEnabled
            ? audio_service.AudioServiceShuffleMode.all
            : audio_service.AudioServiceShuffleMode.none,
        errorMessage: state.error,
      ),
    );
  }

  audio_service.MediaItem _mediaItemFor(
    PlaybackItem item, {
    Duration? durationOverride,
  }) {
    final artworkPath = item.artworkPath?.trim();
    final albumValue = item.audioAsset.metadata['album'];
    final album = albumValue is String && albumValue.trim().isNotEmpty
        ? albumValue.trim()
        : null;

    return audio_service.MediaItem(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album,
      duration: durationOverride ?? item.audioAsset.duration,
      artUri: artworkPath == null || artworkPath.isEmpty
          ? null
          : Uri.file(artworkPath),
      extras: {
        'sourcePath': item.audioAsset.originalPath,
        if (item.projectId != null) 'projectId': item.projectId,
        'hasLyrics': item.hasLyrics,
      },
    );
  }

  audio_service.AudioProcessingState _processingState(
    app_state.PlaybackState state,
  ) {
    if (_sessionState.currentItem == null) {
      return audio_service.AudioProcessingState.idle;
    }
    if (state.error != null) return audio_service.AudioProcessingState.error;
    if (state.isLoading) return audio_service.AudioProcessingState.loading;
    if (state.isBuffering) return audio_service.AudioProcessingState.buffering;
    if (state.isCompleted) return audio_service.AudioProcessingState.completed;
    return audio_service.AudioProcessingState.ready;
  }

  audio_service.AudioServiceRepeatMode _repeatMode(PlaybackRepeatMode mode) {
    return switch (mode) {
      PlaybackRepeatMode.off => audio_service.AudioServiceRepeatMode.none,
      PlaybackRepeatMode.all => audio_service.AudioServiceRepeatMode.all,
      PlaybackRepeatMode.one => audio_service.AudioServiceRepeatMode.one,
    };
  }

  @override
  Future<void> play() async {
    if (_session.currentState.currentItem == null) return;

    final playback = _session.playbackState;
    if (playback.isCompleted) {
      await _session.seek(Duration.zero);
      return;
    }
    if (playback.isPlaying) return;
    await _session.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    if (!_session.playbackState.isPlaying) return;
    await _session.togglePlayPause();
  }

  @override
  Future<void> stop() async {
    // A system stop should silence playback without destroying LyricForge's
    // queue. The user can resume from the app/lock screen later.
    if (_session.playbackState.isPlaying) {
      await _session.togglePlayPause();
    }
  }

  @override
  Future<void> seek(Duration position) => _session.seek(position);

  @override
  Future<void> skipToPrevious() => _session.skipPrevious();

  @override
  Future<void> skipToNext() => _session.skipNext();

  @override
  Future<void> skipToQueueItem(int index) => _session.playAt(index);

  @override
  Future<void> setSpeed(double speed) => _audio.setSpeed(speed);

  @override
  Future<void> setRepeatMode(audio_service.AudioServiceRepeatMode repeatMode) {
    final mode = switch (repeatMode) {
      audio_service.AudioServiceRepeatMode.one => PlaybackRepeatMode.one,
      audio_service.AudioServiceRepeatMode.all ||
      audio_service.AudioServiceRepeatMode.group => PlaybackRepeatMode.all,
      _ => PlaybackRepeatMode.off,
    };
    return _session.setRepeatMode(mode);
  }

  @override
  Future<void> setShuffleMode(audio_service.AudioServiceShuffleMode shuffleMode) {
    return _session.setShuffleEnabled(
      shuffleMode != audio_service.AudioServiceShuffleMode.none,
    );
  }

  Future<void> disposeBridge() async {
    await _sessionSubscription?.cancel();
    await _playerSubscription?.cancel();
  }
}
