import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../domain/models/local_media_metadata.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_session_snapshot.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/repositories/playback_session_store.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

class DefaultPlaybackSessionService implements PlaybackSessionService {
  final AudioPlayerService _audioPlayer;
  final PlayHistoryRepository? _playHistoryRepository;
  final LocalMediaMetadataRepository? _localMediaMetadataRepository;
  final PlaybackSessionStore? _sessionStore;
  final Random _random;
  final _stateController = StreamController<PlaybackSessionState>.broadcast();

  PlaybackSessionState _state = const PlaybackSessionState();
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _sessionPersistTimer;
  Future<void>? _restoreFuture;
  bool _restoring = false;
  bool _disposed = false;
  bool _handledCompletion = false;
  bool _wasPlaying = false;
  Duration? _lastHistorySavedPosition;
  Duration? _lastSessionSavedPosition;
  Duration? _pendingResumePosition;
  String? _loadedItemId;
  List<String>? _unshuffledOrder;

  DefaultPlaybackSessionService(
    this._audioPlayer, {
    PlayHistoryRepository? playHistoryRepository,
    LocalMediaMetadataRepository? localMediaMetadataRepository,
    PlaybackSessionStore? sessionStore,
    Random? random,
  })  : _playHistoryRepository = playHistoryRepository,
        _localMediaMetadataRepository = localMediaMetadataRepository,
        _sessionStore = sessionStore,
        _random = random ?? Random() {
    _playbackSubscription = _audioPlayer.stateStream.listen((playback) {
      if (_restoring || _disposed) return;
      final paused = _wasPlaying && !playback.isPlaying && !playback.isCompleted;
      _wasPlaying = playback.isPlaying;
      if (paused) {
        unawaited(_persistCurrentHistory());
        unawaited(_persistSessionNow());
      }

      if (!playback.isCompleted) {
        _handledCompletion = false;
        return;
      }
      if (_handledCompletion) return;
      _handledCompletion = true;
      unawaited(_handleCompletion());
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (_restoring || _disposed || _state.currentItem == null) return;

      final previousSession = _lastSessionSavedPosition;
      if (previousSession == null ||
          (position.inSeconds - previousSession.inSeconds).abs() >= 10) {
        _lastSessionSavedPosition = position;
        unawaited(_persistSessionNow(position: position));
      }

      final item = _state.currentItem;
      if (item == null || item.projectId != null) return;
      final previous = _lastHistorySavedPosition;
      if (previous == null ||
          (position.inSeconds - previous.inSeconds).abs() >= 15) {
        _lastHistorySavedPosition = position;
        unawaited(_persistCurrentHistory(position: position));
      }
    });

    _restoreFuture = _restorePersistedSession();
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _stateController.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => _audioPlayer.currentState;

  Future<void> _awaitRestore() async {
    final restore = _restoreFuture;
    if (restore != null) await restore;
  }

  bool _isRemotePath(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<bool> _isRestorable(PlaybackItem item) async {
    if (item.isRemoteStream) return true;
    final path = item.audioAsset.originalPath.trim();
    if (path.isEmpty) return false;
    if (_isRemotePath(path)) return true;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      return File(uri.toFilePath()).exists();
    }
    return File(path).exists();
  }

  Future<void> _restorePersistedSession() async {
    final store = _sessionStore;
    if (store == null) return;

    _restoring = true;
    try {
      final snapshot = await store.load();
      if (snapshot == null || snapshot.state.queue.isEmpty) return;

      final originalCurrentId = snapshot.state.currentItem?.id;
      final restored = <PlaybackItem>[];
      for (final item in snapshot.state.queue) {
        if (!await _isRestorable(item)) continue;
        restored.add(await _withLocalMediaMetadata(item));
      }

      if (restored.isEmpty) {
        await store.clear();
        return;
      }

      var currentIndex = originalCurrentId == null
          ? snapshot.state.currentIndex.clamp(0, restored.length - 1).toInt()
          : restored.indexWhere((item) => item.id == originalCurrentId);
      if (currentIndex < 0) {
        currentIndex = snapshot.state.currentIndex
            .clamp(0, restored.length - 1)
            .toInt();
      }

      final restoredIds = restored.map((item) => item.id).toSet();
      final savedUnshuffled = snapshot.unshuffledOrder
          ?.where(restoredIds.contains)
          .toList(growable: true);
      _unshuffledOrder = snapshot.state.shuffleEnabled
          ? (savedUnshuffled == null || savedUnshuffled.isEmpty
              ? restored.map((item) => item.id).toList(growable: true)
              : savedUnshuffled)
          : null;
      _state = PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(restored),
        currentIndex: currentIndex,
        shuffleEnabled: snapshot.state.shuffleEnabled,
        repeatMode: snapshot.state.repeatMode,
      );
      _pendingResumePosition = snapshot.position;
      _lastSessionSavedPosition = snapshot.position;
      _stateController.add(_state);

      final current = _state.currentItem;
      if (current != null && !current.isRemoteStream) {
        try {
          await _loadCurrent(
            resumeFrom: snapshot.position,
            autoplay: false,
            persistHistory: false,
          );
        } catch (_) {
          _loadedItemId = null;
          _pendingResumePosition = snapshot.position;
        }
      }
    } catch (_) {
      // A stale/corrupt session is recoverable state and must never block app
      // startup. The next normal playback mutation will overwrite it.
    } finally {
      _restoring = false;
    }
  }

  void _scheduleSessionPersist() {
    if (_sessionStore == null || _restoring || _disposed) return;
    _sessionPersistTimer?.cancel();
    _sessionPersistTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistSessionNow()),
    );
  }

  Duration _sessionPosition() {
    final current = _state.currentItem;
    if (current == null) return Duration.zero;
    if (_loadedItemId == current.id) return _audioPlayer.currentState.position;
    return _pendingResumePosition ?? Duration.zero;
  }

  Future<void> _persistSessionNow({Duration? position}) async {
    final store = _sessionStore;
    if (store == null || _restoring) return;
    try {
      if (_state.queue.isEmpty || _state.currentItem == null) {
        await store.clear();
        return;
      }
      final resolvedPosition = position ?? _sessionPosition();
      _lastSessionSavedPosition = resolvedPosition;
      await store.save(
        PlaybackSessionSnapshot(
          state: _state,
          position: resolvedPosition < Duration.zero
              ? Duration.zero
              : resolvedPosition,
          unshuffledOrder: _unshuffledOrder == null
              ? null
              : List<String>.unmodifiable(_unshuffledOrder!),
          savedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Session persistence is best-effort and must never interrupt playback.
    }
  }

  void _emit(PlaybackSessionState next) {
    final previousId = _state.currentItem?.id;
    _state = next;
    if (_state.currentItem?.id != previousId) {
      _lastHistorySavedPosition = null;
      _lastSessionSavedPosition = null;
      _pendingResumePosition = null;
      _loadedItemId = null;
      _wasPlaying = false;
    }
    _stateController.add(_state);
    _scheduleSessionPersist();
  }

  Future<PlaybackItem> _withLocalMediaMetadata(PlaybackItem item) async {
    final repository = _localMediaMetadataRepository;
    if (repository == null || item.projectId != null || item.isRemoteStream) {
      return item;
    }

    LocalMediaMetadata? metadata;
    try {
      metadata = await repository.getForAudio(item.audioAsset.originalPath);
    } catch (_) {
      return item;
    }
    if (metadata == null || !metadata.hasOverrides) return item;

    return item.copyWith(
      title: metadata.resolvedTitle(item.title),
      artist: metadata.resolvedArtist(item.artist),
      artworkPath: metadata.resolvedArtwork(item.artworkPath),
    );
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
    if (repository == null ||
        item == null ||
        item.projectId != null ||
        item.isRemoteStream) {
      return;
    }

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

  Future<void> _loadCurrent({
    Duration? resumeFrom,
    bool autoplay = true,
    bool persistHistory = true,
  }) async {
    final item = _state.currentItem;
    if (item == null) return;

    if (item.streamUri != null) {
      await _audioPlayer.loadAudioUri(
        uri: item.streamUri!,
        source: item.preferredSource,
      );
    } else {
      await _audioPlayer.loadProjectAudio(
        audioAsset: item.audioAsset,
        preferredSource: item.preferredSource,
      );
    }
    _loadedItemId = item.id;

    final position = resumeFrom ?? _pendingResumePosition;
    if (position != null && position > Duration.zero) {
      final duration = _audioPlayer.currentState.duration;
      if (duration == null || position < duration) {
        await _audioPlayer.seek(position);
      }
    }
    _pendingResumePosition = null;

    if (autoplay) await _audioPlayer.play();
    if (persistHistory) await _persistCurrentHistory();
    _scheduleSessionPersist();
  }

  Future<void> _ensureCurrentLoaded() async {
    final current = _state.currentItem;
    if (current == null || _loadedItemId == current.id) return;
    await _loadCurrent(
      resumeFrom: _pendingResumePosition,
      autoplay: false,
      persistHistory: false,
    );
  }

  List<PlaybackItem> _shuffleUpcoming(
    List<PlaybackItem> queue,
    int currentIndex,
  ) {
    if (queue.length < 2) return queue;
    final split = (currentIndex + 1).clamp(0, queue.length).toInt();
    final prefix = queue.take(split).toList(growable: false);
    final upcoming = queue.skip(split).toList()..shuffle(_random);
    return <PlaybackItem>[...prefix, ...upcoming];
  }

  List<PlaybackItem> _restoreUnshuffledOrder(List<PlaybackItem> queue) {
    final order = _unshuffledOrder;
    if (order == null || order.isEmpty || queue.isEmpty) return queue;

    final byId = <String, PlaybackItem>{for (final item in queue) item.id: item};
    final restored = <PlaybackItem>[];
    final seen = <String>{};
    for (final id in order) {
      final item = byId[id];
      if (item != null && seen.add(id)) restored.add(item);
    }
    for (final item in queue) {
      if (seen.add(item.id)) restored.add(item);
    }
    return restored;
  }

  void _removeFromUnshuffledOrder(String id) {
    _unshuffledOrder?.removeWhere((itemId) => itemId == id);
  }

  void _syncUnshuffledOrderToQueue(List<PlaybackItem> queue) {
    if (_state.shuffleEnabled) {
      _unshuffledOrder = queue.map((item) => item.id).toList(growable: true);
    }
  }

  Future<void> _playIndex(int index) async {
    await _persistCurrentHistory();
    _emit(_state.copyWith(currentIndex: index));
    _handledCompletion = false;
    await _loadCurrent();
  }

  Future<void> _startNextShuffleCycle() async {
    if (_state.queue.isEmpty) return;
    final currentId = _state.currentItem?.id;
    final base = _restoreUnshuffledOrder(List<PlaybackItem>.from(_state.queue));
    final nextCycle = List<PlaybackItem>.from(base)..shuffle(_random);
    if (nextCycle.length > 1 && nextCycle.first.id == currentId) {
      final swapIndex = 1 + _random.nextInt(nextCycle.length - 1);
      final first = nextCycle.first;
      nextCycle[0] = nextCycle[swapIndex];
      nextCycle[swapIndex] = first;
    }
    await _persistCurrentHistory();
    _emit(
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(nextCycle),
        currentIndex: 0,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  Future<void> _handleCompletion() async {
    await _awaitRestore();
    if (_restoring || _disposed) return;
    await _persistCurrentHistory();
    if (_state.currentItem == null) return;

    if (_state.repeatMode == PlaybackRepeatMode.one) {
      _handledCompletion = false;
      await _loadCurrent();
      return;
    }

    if (_state.currentIndex + 1 < _state.queue.length) {
      await _playIndex(_state.currentIndex + 1);
      return;
    }

    if (_state.repeatMode == PlaybackRepeatMode.all && _state.queue.isNotEmpty) {
      if (_state.shuffleEnabled && _state.queue.length > 1) {
        await _startNextShuffleCycle();
      } else {
        await _playIndex(0);
      }
    }
  }

  @override
  Future<void> playItem(
    PlaybackItem item, {
    Duration? resumeFrom,
  }) async {
    await _awaitRestore();
    if (_state.currentItem?.id != item.id) {
      await _persistCurrentHistory();
    }

    final resolved = await _withLocalMediaMetadata(item);
    final queue = List<PlaybackItem>.from(_state.queue);
    var index = queue.indexWhere((entry) => entry.id == resolved.id);

    if (index >= 0) {
      queue[index] = resolved;
    } else {
      queue.add(resolved);
      index = queue.length - 1;
      if (_state.shuffleEnabled) {
        _unshuffledOrder ??= <String>[];
        if (!_unshuffledOrder!.contains(resolved.id)) {
          _unshuffledOrder!.add(resolved.id);
        }
      }
    }

    _emit(
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: index,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent(resumeFrom: resumeFrom);
  }

  @override
  Future<void> setQueue(
    List<PlaybackItem> items, {
    int startIndex = 0,
  }) async {
    await _awaitRestore();
    await _persistCurrentHistory();
    if (items.isEmpty) {
      _unshuffledOrder = _state.shuffleEnabled ? <String>[] : null;
      _emit(_state.copyWith(queue: const [], currentIndex: -1));
      await _audioPlayer.stop();
      _loadedItemId = null;
      _pendingResumePosition = null;
      await _persistSessionNow();
      return;
    }

    final resolvedItems = await Future.wait(items.map(_withLocalMediaMetadata));
    final safeIndex = startIndex.clamp(0, resolvedItems.length - 1).toInt();
    var queue = List<PlaybackItem>.from(resolvedItems);
    if (_state.shuffleEnabled) {
      _unshuffledOrder = queue.map((item) => item.id).toList(growable: true);
      queue = _shuffleUpcoming(queue, safeIndex);
    } else {
      _unshuffledOrder = null;
    }
    final currentId = resolvedItems[safeIndex].id;
    final shuffledIndex = queue.indexWhere((item) => item.id == currentId);
    _emit(
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: shuffledIndex,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    await _awaitRestore();
    final resolved = await _withLocalMediaMetadata(item);
    final queue = List<PlaybackItem>.from(_state.queue);
    if (queue.every((entry) => entry.id != resolved.id)) {
      queue.add(resolved);
      if (_state.shuffleEnabled) {
        _unshuffledOrder ??= _state.queue.map((entry) => entry.id).toList();
        if (!_unshuffledOrder!.contains(resolved.id)) {
          _unshuffledOrder!.add(resolved.id);
        }
        final currentId = _state.currentItem?.id;
        final shuffled = _shuffleUpcoming(queue, _state.currentIndex);
        final nextIndex = currentId == null
            ? _state.currentIndex
            : shuffled.indexWhere((entry) => entry.id == currentId);
        _emit(
          _state.copyWith(
            queue: List<PlaybackItem>.unmodifiable(shuffled),
            currentIndex: nextIndex,
          ),
        );
        return;
      }
      _emit(
        _state.copyWith(queue: List<PlaybackItem>.unmodifiable(queue)),
      );
    }
  }

  @override
  Future<void> updateItem(PlaybackItem item) async {
    await _awaitRestore();
    final index = _state.queue.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return;

    final queue = List<PlaybackItem>.from(_state.queue);
    queue[index] = item;
    _emit(_state.copyWith(queue: List<PlaybackItem>.unmodifiable(queue)));
    if (index == _state.currentIndex) {
      await _persistCurrentHistory();
    }
  }

  @override
  Future<void> playAt(int index) async {
    await _awaitRestore();
    if (index < 0 || index >= _state.queue.length) return;
    if (index == _state.currentIndex) {
      if (!_audioPlayer.currentState.isPlaying) {
        await _ensureCurrentLoaded();
        await _audioPlayer.play();
      }
      return;
    }
    await _playIndex(index);
  }

  @override
  Future<void> removeAt(int index) async {
    await _awaitRestore();
    if (index < 0 || index >= _state.queue.length) return;

    final queue = List<PlaybackItem>.from(_state.queue);
    final removed = queue[index];
    final removingCurrent = index == _state.currentIndex;
    final removingBeforeCurrent = index < _state.currentIndex;
    if (removingCurrent) {
      await _persistCurrentHistory();
    }
    queue.removeAt(index);
    if (_state.shuffleEnabled) _removeFromUnshuffledOrder(removed.id);

    if (queue.isEmpty) {
      _emit(_state.copyWith(queue: const [], currentIndex: -1));
      _handledCompletion = false;
      _loadedItemId = null;
      _pendingResumePosition = null;
      await _audioPlayer.stop();
      await _persistSessionNow();
      return;
    }

    if (removingCurrent) {
      final nextIndex = index < queue.length ? index : queue.length - 1;
      _emit(
        _state.copyWith(
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
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: nextCurrentIndex,
      ),
    );
  }

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {
    await _awaitRestore();
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
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: currentIndex,
      ),
    );
    _syncUnshuffledOrderToQueue(queue);
    _scheduleSessionPersist();
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {
    await _awaitRestore();
    final current = _state.currentItem;
    if (keepCurrent && current != null) {
      if (_state.shuffleEnabled) _unshuffledOrder = <String>[current.id];
      _emit(
        _state.copyWith(
          queue: List<PlaybackItem>.unmodifiable([current]),
          currentIndex: 0,
        ),
      );
      return;
    }

    await _persistCurrentHistory();
    _unshuffledOrder = _state.shuffleEnabled ? <String>[] : null;
    _emit(_state.copyWith(queue: const [], currentIndex: -1));
    _handledCompletion = false;
    _loadedItemId = null;
    _pendingResumePosition = null;
    await _audioPlayer.stop();
    await _persistSessionNow();
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    await _awaitRestore();
    if (_state.shuffleEnabled == enabled) return;
    final currentId = _state.currentItem?.id;
    var queue = List<PlaybackItem>.from(_state.queue);

    if (enabled) {
      _unshuffledOrder = queue.map((item) => item.id).toList(growable: true);
      queue = _shuffleUpcoming(queue, _state.currentIndex);
    } else {
      queue = _restoreUnshuffledOrder(queue);
      _unshuffledOrder = null;
    }

    final nextIndex = currentId == null
        ? -1
        : queue.indexWhere((item) => item.id == currentId);
    _emit(
      _state.copyWith(
        queue: List<PlaybackItem>.unmodifiable(queue),
        currentIndex: nextIndex,
        shuffleEnabled: enabled,
      ),
    );
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    await _awaitRestore();
    if (_state.repeatMode == mode) return;
    _emit(_state.copyWith(repeatMode: mode));
  }

  @override
  Future<void> skipPrevious() async {
    await _awaitRestore();
    if (_state.currentItem == null) return;

    final position = _loadedItemId == _state.currentItem?.id
        ? _audioPlayer.currentState.position
        : (_pendingResumePosition ?? Duration.zero);
    if (position > const Duration(seconds: 3)) {
      if (_loadedItemId == _state.currentItem?.id) {
        await _audioPlayer.seek(Duration.zero);
      } else {
        _pendingResumePosition = Duration.zero;
      }
      await _persistCurrentHistory(position: Duration.zero);
      await _persistSessionNow(position: Duration.zero);
      return;
    }

    if (_state.currentIndex <= 0) {
      if (_state.repeatMode == PlaybackRepeatMode.all && _state.queue.isNotEmpty) {
        await _playIndex(_state.queue.length - 1);
      } else if (_loadedItemId == _state.currentItem?.id) {
        await _audioPlayer.seek(Duration.zero);
        await _persistCurrentHistory(position: Duration.zero);
        await _persistSessionNow(position: Duration.zero);
      } else {
        _pendingResumePosition = Duration.zero;
        await _persistSessionNow(position: Duration.zero);
      }
      return;
    }

    await _playIndex(_state.currentIndex - 1);
  }

  @override
  Future<void> skipNext() async {
    await _awaitRestore();
    if (_state.currentItem == null) return;
    if (_state.currentIndex + 1 < _state.queue.length) {
      await _playIndex(_state.currentIndex + 1);
      return;
    }

    if (_state.repeatMode == PlaybackRepeatMode.all && _state.queue.isNotEmpty) {
      if (_state.shuffleEnabled && _state.queue.length > 1) {
        await _startNextShuffleCycle();
      } else {
        await _playIndex(0);
      }
    }
  }

  @override
  Future<void> togglePlayPause() async {
    await _awaitRestore();
    if (_state.currentItem == null) return;
    if (_audioPlayer.currentState.isPlaying) {
      await _audioPlayer.pause();
      await _persistSessionNow();
    } else {
      await _ensureCurrentLoaded();
      await _audioPlayer.play();
      _scheduleSessionPersist();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _awaitRestore();
    _lastHistorySavedPosition = position;
    _lastSessionSavedPosition = position;
    if (_state.currentItem == null) return;
    if (_loadedItemId == _state.currentItem?.id) {
      await _audioPlayer.seek(position);
      await _persistCurrentHistory(position: position);
    } else {
      _pendingResumePosition = position;
    }
    await _persistSessionNow(position: position);
  }

  @override
  Future<void> dispose() async {
    await _awaitRestore();
    _sessionPersistTimer?.cancel();
    await _persistCurrentHistory();
    await _persistSessionNow();
    _disposed = true;
    await _positionSubscription?.cancel();
    await _playbackSubscription?.cancel();
    await _stateController.close();
  }
}
