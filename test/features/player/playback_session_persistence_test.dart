import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_playback_session_store.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_session_snapshot.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/playback_session_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('restores local queue, position and modes without autoplay', () async {
    final root = await Directory.systemTemp.createTemp('elysium_session_local_');
    addTearDown(() => root.delete(recursive: true));
    final one = File('${root.path}${Platform.pathSeparator}one.mp3');
    final two = File('${root.path}${Platform.pathSeparator}two.mp3');
    await one.writeAsBytes(const [1]);
    await two.writeAsBytes(const [2]);

    final snapshot = PlaybackSessionSnapshot(
      state: PlaybackSessionState(
        queue: [_localItem('one', one.path), _localItem('two', two.path)],
        currentIndex: 1,
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.one,
      ),
      position: const Duration(seconds: 42),
      unshuffledOrder: const ['one', 'two'],
      savedAt: DateTime(2026, 10, 8),
    );
    final store = _GateSessionStore(snapshot);
    final audio = _FakeAudioPlayer();
    final session = DefaultPlaybackSessionService(audio, sessionStore: store);
    addTearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    final restoredFuture = session.stateStream.first;
    store.release();
    final restored = await restoredFuture;

    expect(restored.queue.map((item) => item.id), ['one', 'two']);
    expect(restored.currentIndex, 1);
    expect(restored.shuffleEnabled, isTrue);
    expect(restored.repeatMode, PlaybackRepeatMode.one);
    for (var attempt = 0;
        attempt < 20 && audio.lastSeek != const Duration(seconds: 42);
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(audio.loadProjectCalls, 1);
    expect(audio.loadUriCalls, 0);
    expect(audio.lastSeek, const Duration(seconds: 42));
    expect(audio.playCalls, 0, reason: 'restore must never autoplay');

    await session.togglePlayPause();
    expect(audio.playCalls, 1);
  });

  test('restored remote stream stays offline until the user presses play', () async {
    final remoteUri = Uri.parse('http://192.168.1.8:4545/v1/tracks/abc/audio?token=t');
    final remote = PlaybackItem(
      id: 'remote:desktop:abc',
      title: 'Remote Song',
      artist: 'Remote Artist',
      streamUri: remoteUri,
      audioAsset: AudioAsset(
        originalPath: remoteUri.toString(),
        format: 'flac',
        duration: const Duration(minutes: 4),
        metadata: const {
          'transferSource': 'media-hub-stream',
          'remoteTrackId': 'abc',
          'remoteArtworkUri':
              'http://192.168.1.8:4545/v1/tracks/abc/artwork?token=t',
        },
      ),
    );
    final store = _GateSessionStore(
      PlaybackSessionSnapshot(
        state: PlaybackSessionState(queue: [remote], currentIndex: 0),
        position: const Duration(seconds: 31),
        savedAt: DateTime(2026, 10, 8),
      ),
    );
    final audio = _FakeAudioPlayer();
    final session = DefaultPlaybackSessionService(audio, sessionStore: store);
    addTearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    final restoredFuture = session.stateStream.first;
    store.release();
    final restored = await restoredFuture;
    expect(restored.currentItem?.id, remote.id);
    expect(audio.loadUriCalls, 0);
    expect(audio.playCalls, 0);

    await session.togglePlayPause();
    expect(audio.loadUriCalls, 1);
    expect(audio.lastLoadedUri, remoteUri);
    expect(audio.lastSeek, const Duration(seconds: 31));
    expect(audio.playCalls, 1);
  });

  test('missing restored current file is pruned and does not leak its position',
      () async {
    final root = await Directory.systemTemp.createTemp('elysium_session_missing_');
    addTearDown(() => root.delete(recursive: true));
    final missing = '${root.path}${Platform.pathSeparator}missing.mp3';
    final existing = File('${root.path}${Platform.pathSeparator}existing.mp3');
    await existing.writeAsBytes(const [1]);

    final store = _GateSessionStore(
      PlaybackSessionSnapshot(
        state: PlaybackSessionState(
          queue: [
            _localItem('missing', missing),
            _localItem('existing', existing.path),
          ],
          currentIndex: 0,
          repeatMode: PlaybackRepeatMode.all,
        ),
        position: const Duration(seconds: 55),
        savedAt: DateTime(2026, 10, 8),
      ),
    );
    final audio = _FakeAudioPlayer();
    final session = DefaultPlaybackSessionService(audio, sessionStore: store);
    addTearDown(() async {
      await session.dispose();
      await audio.dispose();
    });

    final restoredFuture = session.stateStream.first;
    store.release();
    final restored = await restoredFuture;

    expect(restored.queue.map((item) => item.id), ['existing']);
    expect(restored.currentIndex, 0);
    expect(restored.repeatMode, PlaybackRepeatMode.all);
    expect(audio.loadProjectCalls, 1);
    expect(audio.lastSeek, isNull,
        reason: 'the deleted song position must not be applied to another song');
    expect(audio.playCalls, 0);
  });

  test('session mutations persist queue, position, shuffle and repeat', () async {
    final root = await Directory.systemTemp.createTemp('elysium_session_save_');
    addTearDown(() => root.delete(recursive: true));
    final one = File('${root.path}${Platform.pathSeparator}one.mp3');
    final two = File('${root.path}${Platform.pathSeparator}two.mp3');
    await one.writeAsBytes(const [1]);
    await two.writeAsBytes(const [2]);

    final store = _GateSessionStore(null);
    final audio = _FakeAudioPlayer();
    final session = DefaultPlaybackSessionService(audio, sessionStore: store);
    addTearDown(() async {
      await session.dispose();
      await audio.dispose();
    });
    store.release();

    await session.setQueue(
      [_localItem('one', one.path), _localItem('two', two.path)],
      startIndex: 0,
    );
    await session.seek(const Duration(seconds: 18));
    await session.setShuffleEnabled(true);
    await session.setRepeatMode(PlaybackRepeatMode.all);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final saved = store.lastSaved;
    expect(saved, isNotNull);
    expect(saved!.state.queue.length, 2);
    expect(saved.state.currentItem?.id, 'one');
    expect(saved.state.shuffleEnabled, isTrue);
    expect(saved.state.repeatMode, PlaybackRepeatMode.all);
    expect(saved.position, const Duration(seconds: 18));
  });

  test('file store round-trips local and remote playback items', () async {
    final root = await Directory.systemTemp.createTemp('elysium_session_store_');
    addTearDown(() => root.delete(recursive: true));
    final store = FilePlaybackSessionStore(rootDirectory: root);
    final remoteUri = Uri.parse('https://desktop.test/v1/tracks/r1/audio?token=secret');
    final snapshot = PlaybackSessionSnapshot(
      state: PlaybackSessionState(
        queue: [
          PlaybackItem(
            id: 'remote:r1',
            title: 'R1',
            artist: 'Artist',
            streamUri: remoteUri,
            hasLyrics: true,
            preferredSource: AudioSourceType.original,
            audioAsset: AudioAsset(
              originalPath: remoteUri.toString(),
              format: 'flac',
              duration: const Duration(seconds: 90),
              metadata: const {
                'album': 'Album',
                'remoteTrackId': 'r1',
              },
            ),
          ),
        ],
        currentIndex: 0,
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.one,
      ),
      position: const Duration(seconds: 12),
      unshuffledOrder: const ['remote:r1'],
      savedAt: DateTime.utc(2026, 10, 8, 1),
    );

    await store.save(snapshot);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.state.currentItem?.id, 'remote:r1');
    expect(loaded.state.currentItem?.streamUri, remoteUri);
    expect(loaded.state.currentItem?.audioAsset.metadata['album'], 'Album');
    expect(loaded.state.shuffleEnabled, isTrue);
    expect(loaded.state.repeatMode, PlaybackRepeatMode.one);
    expect(loaded.position, const Duration(seconds: 12));
    expect(loaded.unshuffledOrder, ['remote:r1']);
  });
}

PlaybackItem _localItem(String id, String path) {
  return PlaybackItem(
    id: id,
    title: id,
    audioAsset: AudioAsset(
      originalPath: path,
      format: 'mp3',
      duration: const Duration(minutes: 3),
    ),
  );
}

class _GateSessionStore implements PlaybackSessionStore {
  final PlaybackSessionSnapshot? initial;
  final Completer<void> _gate = Completer<void>();
  PlaybackSessionSnapshot? lastSaved;
  int clearCalls = 0;

  _GateSessionStore(this.initial);

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<PlaybackSessionSnapshot?> load() async {
    await _gate.future;
    return initial;
  }

  @override
  Future<void> save(PlaybackSessionSnapshot snapshot) async {
    lastSaved = snapshot;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    lastSaved = null;
  }
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  PlaybackState _state = const PlaybackState.idle();
  int loadProjectCalls = 0;
  int loadUriCalls = 0;
  int playCalls = 0;
  Uri? lastLoadedUri;
  Duration? lastSeek;

  void _emit(PlaybackState next) {
    _state = next;
    _stateController.add(next);
  }

  @override
  PlaybackState get currentState => _state;

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
    loadProjectCalls++;
    _emit(
      _state.copyWith(
        isPlaying: false,
        position: Duration.zero,
        duration: audioAsset.duration ?? const Duration(minutes: 3),
        currentSource: preferredSource,
      ),
    );
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    loadUriCalls++;
    lastLoadedUri = uri;
    _emit(
      _state.copyWith(
        isPlaying: false,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
        currentSource: source,
      ),
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    _emit(_state.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    _emit(_state.copyWith(isPlaying: false));
  }

  @override
  Future<void> stop() async {
    _emit(const PlaybackState.idle());
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    _emit(_state.copyWith(position: position));
    _positionController.add(position);
  }

  @override
  Future<void> switchSource(AudioSourceType source) async {
    _emit(_state.copyWith(currentSource: source));
  }

  @override
  Future<void> setSpeed(double speed) async {
    _emit(_state.copyWith(speed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    _emit(_state.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
