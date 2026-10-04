import 'dart:async';

import '../../domain/models/play_history.dart';
import '../../domain/models/playback_session_snapshot.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/remote_playback_source.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/repositories/playback_session_snapshot_repository.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

class PlaybackSessionPersistenceCoordinator {
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final PlaybackSessionSnapshotRepository snapshots;
  final PlayHistoryRepository playHistory;

  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlaybackState>? _audioSubscription;

  Duration? _lastSavedPosition;
  bool _lastPlaying = false;
  bool _lastObservedWasLocal = false;
  bool _started = false;

  PlaybackSessionPersistenceCoordinator({
    required this.session,
    required this.audio,
    required this.snapshots,
    required this.playHistory,
  });

  bool _isLocal(PlaybackItem item) {
    return item.projectId == null &&
        !RemotePlaybackSource.isRemote(item.audioAsset);
  }

  Future<void> restore() async {
    final snapshot = await snapshots.load();
    if (snapshot == null || snapshot.items.isEmpty) return;

    final items = snapshot.items
        .map((item) => item.toPlaybackItem())
        .toList(growable: false);
    if (items.isEmpty) return;

    final previousVolume = audio.currentState.volume;
    try {
      // Restore before runApp/system media registration. setQueue normally
      // starts playback, so mute it first, pause immediately, seek, then return
      // the user's volume. No startup audio leaks to the user.
      await audio.setVolume(0);
      await session.setQueue(
        items,
        startIndex: snapshot.currentIndex.clamp(0, items.length - 1).toInt(),
      );
      await audio.pause();

      final duration = audio.currentState.duration;
      var position = snapshot.position;
      if (position < Duration.zero) position = Duration.zero;
      if (duration != null && duration > Duration.zero && position >= duration) {
        position = Duration.zero;
      }
      if (position > Duration.zero) {
        await session.seek(position);
      }

      await session.setRepeatMode(snapshot.repeatMode);
      if (snapshot.shuffleEnabled) {
        await session.setShuffleEnabled(true);
      }

      // DefaultPlaybackSessionService records play/pause history asynchronously.
      // Let those callbacks enqueue their writes first, then make the snapshot's
      // original timestamp the final serialized history write. Merely restoring
      // the app must not make an old song appear as "just played".
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final current = session.currentState.currentItem;
      if (current != null && _isLocal(current)) {
        await playHistory.savePlayHistory(
          PlayHistory(
            id: current.id,
            name: current.title,
            artist: current.artist,
            filePath: current.audioAsset.originalPath,
            playedAt: snapshot.savedAt,
            lastPosition: position,
            duration: audio.currentState.duration ?? current.audioAsset.duration,
            lastSource: audio.currentState.currentSource ?? current.preferredSource,
          ),
        );
      }
      _lastSavedPosition = position;
      _lastObservedWasLocal = true;
    } catch (_) {
      // A stale/corrupt snapshot must never block app startup.
      await snapshots.clear();
      try {
        await session.clearQueue(keepCurrent: false);
      } catch (_) {}
    } finally {
      try {
        await audio.setVolume(previousVolume);
      } catch (_) {}
    }
  }

  void start() {
    if (_started) return;
    _started = true;
    _lastPlaying = audio.currentState.isPlaying;

    _sessionSubscription = session.stateStream.listen((state) {
      final current = state.currentItem;
      if (current != null && _isLocal(current)) {
        _lastObservedWasLocal = true;
        unawaited(_persist(position: audio.currentState.position));
        return;
      }

      if (state.queue.isEmpty && _lastObservedWasLocal) {
        _lastObservedWasLocal = false;
        _lastSavedPosition = null;
        unawaited(snapshots.clear());
        return;
      }

      // Remote streams / lyric projects do not overwrite the last local
      // session. If they later clear their own queue, the local snapshot stays.
      _lastObservedWasLocal = false;
    });

    _positionSubscription = audio.positionStream.listen((position) {
      final current = session.currentState.currentItem;
      if (current == null || !_isLocal(current)) return;
      final previous = _lastSavedPosition;
      if (previous == null ||
          (position.inSeconds - previous.inSeconds).abs() >= 5) {
        _lastSavedPosition = position;
        unawaited(_persist(position: position));
      }
    });

    _audioSubscription = audio.stateStream.listen((state) {
      final paused = _lastPlaying && !state.isPlaying && !state.isCompleted;
      _lastPlaying = state.isPlaying;
      if (paused) {
        final current = session.currentState.currentItem;
        if (current != null && _isLocal(current)) {
          unawaited(_persist(position: state.position));
        }
      }
    });
  }

  Future<void> _persist({Duration? position}) async {
    final state = session.currentState;
    final current = state.currentItem;
    if (current == null || !_isLocal(current)) return;

    final localItems = <PlaybackItem>[];
    for (final item in state.queue) {
      if (_isLocal(item)) localItems.add(item);
    }
    if (localItems.isEmpty) return;

    final currentIndex = localItems.indexWhere((item) => item.id == current.id);
    if (currentIndex < 0) return;

    final snapshot = PlaybackSessionSnapshot(
      items: localItems
          .map(PlaybackSessionItemSnapshot.fromPlaybackItem)
          .toList(growable: false),
      currentIndex: currentIndex,
      position: position ?? audio.currentState.position,
      shuffleEnabled: state.shuffleEnabled,
      repeatMode: state.repeatMode,
      savedAt: DateTime.now(),
    );
    await snapshots.save(snapshot);
  }

  Future<void> dispose() async {
    final current = session.currentState.currentItem;
    if (current != null && _isLocal(current)) {
      try {
        await _persist(position: audio.currentState.position);
      } catch (_) {}
    }
    await _sessionSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _audioSubscription?.cancel();
  }
}
