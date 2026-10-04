import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/playback_session_persistence_coordinator.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_session_snapshot.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/remote_playback_source.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/playback_session_snapshot_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late _FakeAudioPlayer audio;
  late _FakePlaybackSession session;
  late _MemorySnapshotRepository snapshots;
  late _MemoryPlayHistoryRepository history;
  late PlaybackSessionPersistenceCoordinator coordinator;

  setUp(() {
    audio = _FakeAudioPlayer(initialVolume: 0.65);
    session = _FakePlaybackSession(audio);
    snapshots = _MemorySnapshotRepository();
    history = _MemoryPlayHistoryRepository();
    coordinator = PlaybackSessionPersistenceCoordinator(
      session: session,
      audio: audio,
      snapshots: snapshots,
      playHistory: history,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await session.dispose();
    await audio.dispose();
  });

  test('restores local queue paused with index position modes and volume', () async {
    final savedAt = DateTime.utc(2026, 10, 3, 14, 20);
    snapshots.value = PlaybackSessionSnapshot(
      items: [
        _snapshotItem('/music/一.mp3', '第一首'),
        _snapshotItem('/music/two.flac', 'Second', artist: 'Artist'),
      ],
      currentIndex: 1,
      position: const Duration(seconds: 73),
      shuffleEnabled: true,
      repeatMode: PlaybackRepeatMode.all,
      savedAt: savedAt,
    );

    await coordinator.restore();

    expect(session.currentState.queue, hasLength(2));
    expect(session.currentState.currentIndex, 1);
    expect(session.currentState.currentItem!.title, 'Second');
    expect(session.currentState.shuffleEnabled, isTrue);
    expect(session.currentState.repeatMode, PlaybackRepeatMode.all);
    expect(audio.currentState.position, const Duration(seconds: 73));
    expect(audio.currentState.isPlaying, isFalse);
    expect(audio.currentState.volume, closeTo(0.65, 0.0001));
    expect(history.saved, isNotEmpty);
    expect(history.saved.last.playedAt, savedAt);
    expect(history.saved.last.lastPosition, const Duration(seconds: 73));
  });

  test('position beyond duration restores at zero and remains paused', () async {
    snapshots.value = PlaybackSessionSnapshot(
      items: [_snapshotItem('/music/a.mp3', 'A')],
      currentIndex: 0,
      position: const Duration(minutes: 10),
      shuffleEnabled: false,
      repeatMode: PlaybackRepeatMode.off,
      savedAt: DateTime.utc(2026, 10, 3),
    );

    await coordinator.restore();

    expect(audio.currentState.duration, const Duration(minutes: 4));
    expect(audio.currentState.position, Duration.zero);
    expect(audio.currentState.isPlaying, isFalse);
  });

  test('live local queue, modes and position are checkpointed', () async {
    coordinator.start();
    await session.setQueue([
      _localItem('/music/one.mp3', 'One'),
      _localItem('/music/two.mp3', 'Two'),
    ], startIndex: 1);
    await session.setRepeatMode(PlaybackRepeatMode.one);
    await session.setShuffleEnabled(true);
    await session.seek(const Duration(seconds: 11));
    await _drain();

    final saved = snapshots.value;
    expect(saved, isNotNull);
    expect(saved!.items.map((item) => item.title), ['One', 'Two']);
    expect(saved.currentIndex, 1);
    expect(saved.position, const Duration(seconds: 11));
    expect(saved.repeatMode, PlaybackRepeatMode.one);
    expect(saved.shuffleEnabled, isTrue);
  });

  test('remote and lyric-project playback do not overwrite local snapshot', () async {
    coordinator.start();
    await session.setQueue([_localItem('/music/local.mp3', 'Local')]);
    await session.seek(const Duration(seconds: 9));
    await _drain();
    final localSnapshot = snapshots.value;
    final saveCount = snapshots.saveCount;

    final remote = PlaybackItem(
      id: 'remote:track',
      title: 'Remote',
      projectId: 'mediahub:track',
      audioAsset: AudioAsset(
        originalPath: 'mediahub://track',
        format: 'mp3',
        metadata: const {
          RemotePlaybackSource.markerKey: true,
          RemotePlaybackSource.streamUriKey:
              'http://127.0.0.1:9988/audio?token=secret',
        },
      ),
    );
    await session.setQueue([remote]);
    await session.seek(const Duration(seconds: 20));
    await _drain();

    expect(snapshots.saveCount, saveCount);
    expect(snapshots.value!.items.single.title, localSnapshot!.items.single.title);
    expect(
      snapshots.value!.items.single.audioAsset.metadata.values,
      isNot(contains('http://127.0.0.1:9988/audio?token=secret')),
    );

    final project = PlaybackItem(
      id: 'project:p1',
      title: 'Project',
      projectId: 'p1',
      audioAsset: const AudioAsset(
        originalPath: '/project/audio.wav',
        format: 'wav',
      ),
    );
    await session.setQueue([project]);
    await _drain();
    expect(snapshots.saveCount, saveCount);
  });

  test('clearing a local queue clears its persisted snapshot', () async {
    coordinator.start();
    await session.setQueue([_localItem('/music/local.mp3', 'Local')]);
    await _drain();
    expect(snapshots.value, isNotNull);

    await session.clearQueue(keepCurrent: false);
    await _drain();

    expect(snapshots.value, isNull);
    expect(snapshots.clearCount, greaterThan(0));
  });

  test('snapshot storage failure does not block startup', () async {
    snapshots.throwOnLoad = true;

    await expectLater(coordinator.restore(), completes);

    expect(session.currentState.queue, isEmpty);
    expect(audio.currentState.isPlaying, isFalse);
  });
}

Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 10));

PlaybackSessionItemSnapshot _snapshotItem(
  String path,
  String title, {
  String? artist,
}) {
  return PlaybackSessionItemSnapshot(
    id: 'local:$path',
    title: title,
    artist: artist,
    audioAsset: AudioAsset(
      originalPath: path,
      format: path.split('.').last,
      duration: const Duration(minutes: 4),
    ),
  );
}

PlaybackItem _localItem(String path, String title) {
  return PlaybackItem(
    id: 'local:$path',
    title: title,
    audioAsset: AudioAsset(
      originalPath: path,
      format: path.split('.').last,
      duration: const Duration(minutes: 4),
    ),
  );
}

class _MemorySnapshotRepository implements PlaybackSessionSnapshotRepository {
  PlaybackSessionSnapshot? value;
  int saveCount = 0;
  int clearCount = 0;
  bool throwOnLoad = false;

  @override
  Future<PlaybackSessionSnapshot?> load() async {
    if (throwOnLoad) throw StateError('disk unavailable');
    return value;
  }

  @override
  Future<void> save(PlaybackSessionSnapshot snapshot) async {
    saveCount++;
    value = snapshot;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    value = null;
  }
}

class _MemoryPlayHistoryRepository implements PlayHistoryRepository {
  final List<PlayHistory> saved = [];

  @override
  Future<void> savePlayHistory(PlayHistory history) async {
    saved.add(history);
  }

  @override
  Future<void> clearPlayHistory() async => saved.clear();

  @override
  Future<PlayHistory?> getPlayHistoryById(String id) async {
    for (final item in saved.reversed) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    return saved.reversed.take(limit).toList(growable: false);
  }

  @override
  Future<void> removePlayHistory(String id) async {
    saved.removeWhere((item) => item.id == id);
  }
}

class _FakePlaybackSession implements PlaybackSessionService {
  final _FakeAudioPlayer audio;
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state = const PlaybackSessionState();

  _FakePlaybackSession(this.audio);

  void _emit(PlaybackSessionState state) {
    _state = state;
    _controller.add(state);
  }

  Future<void> _loadCurrent() async {
    final current = _state.currentItem;
    if (current == null) return;
    await audio.loadProjectAudio(
      audioAsset: current.audioAsset,
      preferredSource: current.preferredSource,
    );
    await audio.play();
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => audio.currentState;

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    if (items.isEmpty) {
      _emit(_state.copyWith(queue: const [], currentIndex: -1));
      await audio.stop();
      return;
    }
    _emit(
      PlaybackSessionState(
        queue: List.unmodifiable(items),
        currentIndex: startIndex.clamp(0, items.length - 1).toInt(),
        shuffleEnabled: _state.shuffleEnabled,
        repeatMode: _state.repeatMode,
      ),
    );
    await _loadCurrent();
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    await setQueue([item]);
    if (resumeFrom != null) await seek(resumeFrom);
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final queue = [..._state.queue, item];
    _emit(_state.copyWith(queue: List.unmodifiable(queue)));
  }

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final queue = [..._state.queue];
    final index = queue.indexWhere((entry) => entry.id == item.id);
    if (index < 0) return;
    queue[index] = item;
    _emit(_state.copyWith(queue: List.unmodifiable(queue)));
  }

  @override
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    _emit(_state.copyWith(currentIndex: index));
    await _loadCurrent();
  }

  @override
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    final queue = [..._state.queue]..removeAt(index);
    if (queue.isEmpty) {
      await clearQueue(keepCurrent: false);
      return;
    }
    final nextIndex = _state.currentIndex.clamp(0, queue.length - 1).toInt();
    _emit(
      _state.copyWith(
        queue: List.unmodifiable(queue),
        currentIndex: nextIndex,
      ),
    );
  }

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {
    final queue = [..._state.queue];
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    _emit(_state.copyWith(queue: List.unmodifiable(queue)));
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {
    final current = _state.currentItem;
    if (keepCurrent && current != null) {
      _emit(
        _state.copyWith(
          queue: List.unmodifiable([current]),
          currentIndex: 0,
        ),
      );
      return;
    }
    _emit(_state.copyWith(queue: const [], currentIndex: -1));
    await audio.stop();
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    _emit(_state.copyWith(shuffleEnabled: enabled));
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _emit(_state.copyWith(repeatMode: mode));
  }

  @override
  Future<void> skipPrevious() async {
    if (_state.currentIndex > 0) await playAt(_state.currentIndex - 1);
  }

  @override
  Future<void> skipNext() async {
    if (_state.currentIndex + 1 < _state.queue.length) {
      await playAt(_state.currentIndex + 1);
    }
  }

  @override
  Future<void> togglePlayPause() async {
    if (audio.currentState.isPlaying) {
      await audio.pause();
    } else {
      await audio.play();
    }
  }

  @override
  Future<void> seek(Duration position) => audio.seek(position);

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  PlaybackState _current;

  _FakeAudioPlayer({double initialVolume = 1.0})
      : _current = PlaybackState(
          isPlaying: false,
          isBuffering: false,
          isCompleted: false,
          isLoading: false,
          position: Duration.zero,
          duration: null,
          bufferedPosition: Duration.zero,
          speed: 1.0,
          volume: initialVolume,
          currentSource: AudioSourceType.original,
        );

  void _emit(PlaybackState next, {bool position = false}) {
    _current = next;
    _stateController.add(next);
    if (position) _positionController.add(next.position);
    _durationController.add(next.duration);
  }

  @override
  PlaybackState get currentState => _current;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    _emit(
      PlaybackState(
        isPlaying: false,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: Duration.zero,
        duration: audioAsset.duration ?? const Duration(minutes: 4),
        bufferedPosition: Duration.zero,
        speed: _current.speed,
        volume: _current.volume,
        currentSource: preferredSource,
      ),
    );
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> play() async {
    _emit(_current.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    _emit(_current.copyWith(isPlaying: false));
  }

  @override
  Future<void> stop() async {
    _emit(
      PlaybackState(
        isPlaying: false,
        isBuffering: false,
        isCompleted: false,
        isLoading: false,
        position: Duration.zero,
        duration: _current.duration,
        bufferedPosition: Duration.zero,
        speed: _current.speed,
        volume: _current.volume,
        currentSource: _current.currentSource,
      ),
      position: true,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _emit(_current.copyWith(position: position), position: true);
  }

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> setSpeed(double speed) async {
    _emit(_current.copyWith(speed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    _emit(_current.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
