import 'dart:async';

import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

class DefaultPlaybackSessionService implements PlaybackSessionService {
  final AudioPlayerService _audioPlayer;
  final PlayHistoryRepository? _playHistoryRepository;
  final _stateController =
      StreamController<PlaybackSessionState>.broadcast();

  PlaybackSessionState _state = const PlaybackSessionState();
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool _handledCompletion = false;
  bool _wasPlaying = false;
  Duration? _lastHistorySavedPosition;

  DefaultPlaybackSessionService(
    this._audioPlayer, {
    PlayHistoryRepository? playHistoryRepository,
  }) : _playHistoryRepository = playHistoryRepository {
    _playbackSubscription = _audioPlayer.stateStream.listen((playback) {
      final paused = _wasPlaying && !playback.isPlaying && !playback.isCompleted;
      _wasPlaying = playback.isPlaying;
      if (paused) {
        unawaited(_persistCurrentHistory());
      }

      if (!playback.isCompleted) {
        _handledCompletion = false;
        return;
      }
      if (_handledCompletion) return;
      _handledCompletion = true;
      unawaited(_persistCurrentHistory());
      if (_state.canSkipNext) {
        unawaited(skipNext());
      }
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      final item = _state.currentItem;
      if (item == null || item.projectId != null) return;

      final previous = _lastHistorySavedPosition;
      if (previous == null ||
          (position.inSeconds - previous.inSeconds).abs() >= 15) {
        _lastHistorySavedPosition = position;
        unawaited(_persistCurrentHistory(position: position));
      }
    });
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _stateController.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => _audioPlayer.currentState;

  void _emit(PlaybackSessionState next) {
    final previousId = _state.currentItem?.id;
    _state = next;
    if (_state.currentItem?.id != previousId) {
      _lastHistorySavedPosition = null;
      _wasPlaying = false;
    }
    _stateController.add(_state);
  }

  Duration _historyPosition(PlaybackState playback, Duration position) {
    final duration = playback.duration;
    if (duration != null && duration > Duration.zero) {
      final remaining = duration - position;
      if (remaining <= const Duration(seconds: 3)) {
        return Duration.zero;
      }
    }
    return position < Duration.zero ? Duration.zero : position;
  }

  Future<void> _persistCurrentHistory({Duration? position}) async {
    final repository = _playHistoryRepository;
    final item = _state.currentItem;
    if (repository == null || item == null || item.projectId != null) return;

    final playback = _audioPlayer.currentState;
    final resolvedPosition = _historyPosition(
      playback,
      position ?? playback.position,
    );
    _lastHistorySavedPosition = resolvedPosition;

    try {
      await repository.savePlayHistory(
        PlayHistory(
          id: item.id,
          name: item.title,
          artist: item.artist,
          filePath: item.audioAsset.originalPath,
          playedAt: DateTime.now(),
          lastPosition: resolvedPosition,
          duration: playback.duration,
          lastSource: playback.currentSource ?? item.preferredSource,
        ),
      );
    } catch (_) {
      // Playback must never fail because non-critical recent-play metadata could
      // not be persisted.
    }
  }

  Future<void> _loadCurrent({Duration? resumeFrom}) async {
    final item = _state.currentItem;
    if (item == null) return;

    await _audioPlayer.loadProjectAudio(
      audioAsset: item.audioAsset,
      preferredSource: item.preferredSource,
    );

    if (resumeFrom != null && resumeFrom > Duration.zero) {
      final duration = _audioPlayer.currentState.duration;
      if (duration == null || resumeFrom < duration) {
        await _audioPlayer.seek(resumeFrom);
      }
    }

    await _audioPlayer.play();
    await _persistCurrentHistory();
  }

  @override
  Future<void> playItem(
    PlaybackItem item, {
    Duration? resumeFrom,
  }) async {
    if (_state.currentItem?.id != item.id) {
      await _persistCurrentHistory();
    }

    final queue = List<PlaybackItem>.from(_state.queue);
    var index = queue.indexWhere((entry) => entry.id == item.id);

    if (index >= 0) {
      queue[index] = item;
    } else {
      queue.add(item);
      index = queue.length - 1;
    }

    _emit(PlaybackSessionState(queue: queue, currentIndex: index));
    _handledCompletion = false;
    await _loadCurrent(resumeFrom: resumeFrom);
  }

  @override
  Future<void> setQueue(
    List<PlaybackItem> items, {
    int startIndex = 0,
  }) async {
    await _persistCurrentHistory();
    if (items.isEmpty) {
      _emit(const PlaybackSessionState());
      await _audioPlayer.stop();
      return;
    }

    final safeIndex = startIndex.clamp(0, items.length - 1).toInt();
    _emit(
      PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(items),
        currentIndex: safeIndex,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final queue = List<PlaybackItem>.from(_state.queue);
    if (queue.every((entry) => entry.id != item.id)) {
      queue.add(item);
      _emit(
        PlaybackSessionState(
          queue: List<PlaybackItem>.unmodifiable(queue),
          currentIndex: _state.currentIndex,
        ),
      );
    }
  }

  @override
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    if (index == _state.currentIndex) return;

    await _persistCurrentHistory();
    _emit(
      PlaybackSessionState(
        queue: _state.queue,
        currentIndex: index,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _state.queue.length) return;

    final queue = List<PlaybackItem>.from(_state.queue);
    final removingCurrent = index == _state.currentIndex;
    final removingBeforeCurrent = index < _state.currentIndex;
    if (removingCurrent) {
      await _persistCurrentHistory();
    }
    queue.removeAt(index);

    if (queue.isEmpty) {
      _emit(const PlaybackSessionState());
      _handledCompletion = false;
      await _audioPlayer.stop();
      return;
    }

    if (removingCurrent) {
      final nextIndex = index < queue.length ? index : queue.length - 1;
      _emit(
        PlaybackSessionState(
          queue: List<PlaybackItem>.unmodifiable(queue),
          currentIndex: nextIndex,
        ),
      );
      _handledCompletion = false;
      await _loadCurrent();
      return;
    }

    final nextCurrentIndex =
        removingBeforeCurrent ? _state.currentIndex - 1 : _state.currentIndex;
    _emit(
      PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: nextCurrentIndex,
      ),
    );
  }

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {
    final length = _state.queue.length;
    if (oldIndex < 0 || oldIndex >= length || newIndex < 0 || newIndex >= length) {
      return;
    }
    if (oldIndex == newIndex) return;

    final currentId = _state.currentItem?.id;
    final queue = List<PlaybackItem>.from(_state.queue);
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);

    final currentIndex = currentId == null
        ? -1
        : queue.indexWhere((entry) => entry.id == currentId);
    _emit(
      PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: currentIndex,
      ),
    );
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {
    final current = _state.currentItem;
    if (keepCurrent && current != null) {
      _emit(
        PlaybackSessionState(
          queue: List<PlaybackItem>.unmodifiable([current]),
          currentIndex: 0,
        ),
      );
      return;
    }

    await _persistCurrentHistory();
    _emit(const PlaybackSessionState());
    _handledCompletion = false;
    await _audioPlayer.stop();
  }

  @override
  Future<void> skipPrevious() async {
    if (_state.currentItem == null) return;

    if (_audioPlayer.currentState.position > const Duration(seconds: 3)) {
      await _audioPlayer.seek(Duration.zero);
      await _persistCurrentHistory(position: Duration.zero);
      return;
    }

    if (_state.currentIndex <= 0) {
      await _audioPlayer.seek(Duration.zero);
      await _persistCurrentHistory(position: Duration.zero);
      return;
    }

    await _persistCurrentHistory();
    _emit(
      PlaybackSessionState(
        queue: _state.queue,
        currentIndex: _state.currentIndex - 1,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> skipNext() async {
    if (!_state.canSkipNext) return;

    await _persistCurrentHistory();
    _emit(
      PlaybackSessionState(
        queue: _state.queue,
        currentIndex: _state.currentIndex + 1,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> togglePlayPause() async {
    if (_audioPlayer.currentState.isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _lastHistorySavedPosition = position;
    await _audioPlayer.seek(position);
    await _persistCurrentHistory(position: position);
  }

  @override
  Future<void> dispose() async {
    await _persistCurrentHistory();
    await _positionSubscription?.cancel();
    await _playbackSubscription?.cancel();
    await _stateController.close();
  }
}
