import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/default_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/data/services/library_metadata_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/data/services/remote_rebinding_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_session_snapshot.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/playback_session_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/project_audio_source_update.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/remote_playback_item_resolver.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

const oldAsset = AudioAsset(
  originalPath: '/song.wav',
  normalizedPath: '/normalized.wav',
  format: 'wav',
  duration: Duration(minutes: 3),
  metadata: {'source': 'queue'},
);
const newAsset = AudioAsset(
  originalPath: '/song.wav',
  instrumentalPath: '/backing.wav',
  format: 'mp3',
  metadata: {'source': 'stale project'},
);

PlaybackItem projectItem({
  String id = 'item',
  String projectId = 'project',
  AudioAsset asset = oldAsset,
  Uri? stream,
}) => PlaybackItem(
  id: id,
  title: 'Current title',
  artist: 'Current artist',
  projectId: projectId,
  hasLyrics: true,
  artworkPath: '/art.png',
  audioAsset: asset,
  streamUri: stream,
);

void main() {
  for (final paused in [false, true]) {
    test(
      'updates active project without interrupting ${paused ? 'paused' : 'playing'} session',
      () async {
        final audio = _Audio();
        final store = _Store();
        final session = DefaultPlaybackSessionService(
          audio,
          sessionStore: store,
        );
        final item = projectItem();
        await session.setQueue([
          item,
          projectItem(id: 'next', projectId: 'next-project'),
        ]);
        await session.setShuffleEnabled(true);
        await session.setRepeatMode(PlaybackRepeatMode.one);
        await session.seek(const Duration(seconds: 42));
        if (paused) await session.togglePlayPause();
        final before = session.currentState;
        final beforeAudio = audio.currentState;
        final loadCalls = audio.loadCalls,
            playCalls = audio.playCalls,
            pauseCalls = audio.pauseCalls,
            seekCalls = audio.seekCalls;

        expect(
          await session.updateActiveProjectSources(
            projectId: 'project',
            expected: oldAsset,
            replacement: newAsset,
          ),
          isTrue,
        );
        final after = session.currentState;
        expect(
          after.queue.map((item) => item.id),
          before.queue.map((item) => item.id),
        );
        expect(after.currentIndex, before.currentIndex);
        expect(after.shuffleEnabled, isTrue);
        expect(after.repeatMode, PlaybackRepeatMode.one);
        expect(after.currentItem!.title, 'Current title');
        expect(after.currentItem!.artist, 'Current artist');
        expect(after.currentItem!.artworkPath, '/art.png');
        expect(after.currentItem!.hasLyrics, isTrue);
        expect(after.currentItem!.audioAsset.instrumentalPath, '/backing.wav');
        expect(after.currentItem!.audioAsset.format, 'wav');
        expect(
          after.currentItem!.audioAsset.duration,
          const Duration(minutes: 3),
        );
        expect(after.currentItem!.audioAsset.normalizedPath, '/normalized.wav');
        expect(after.currentItem!.audioAsset.metadata, {'source': 'queue'});
        expect(audio.asset, same(after.currentItem!.audioAsset));
        expect(audio.currentState.position, beforeAudio.position);
        expect(audio.currentState.isPlaying, beforeAudio.isPlaying);
        expect(
          [audio.loadCalls, audio.playCalls, audio.pauseCalls, audio.seekCalls],
          [loadCalls, playCalls, pauseCalls, seekCalls],
        );
        await session.dispose();
        expect(
          store.saved!.state.currentItem!.audioAsset.instrumentalPath,
          '/backing.wav',
        );
        expect(store.saved!.position, const Duration(seconds: 42));
      },
    );
  }

  test(
    'rejects mismatched project, stale snapshot, and backend refusal',
    () async {
      final audio = _Audio();
      final session = DefaultPlaybackSessionService(audio);
      addTearDown(session.dispose);
      await session.setQueue([projectItem()]);
      expect(
        await session.updateActiveProjectSources(
          projectId: 'wrong',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: newAsset,
          replacement: oldAsset,
        ),
        isFalse,
      );
      expect(audio.updateCalls, 0);
      audio.reject = true;
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(
        session.currentState.currentItem!.audioAsset.instrumentalPath,
        isNull,
      );
      expect(audio.asset!.instrumentalPath, isNull);
    },
  );

  test(
    'refuses a change to the active source and can clear an inactive source',
    () async {
      const withBacking = AudioAsset(
        originalPath: '/song.wav',
        instrumentalPath: '/old.wav',
        format: 'wav',
      );
      final audio = _Audio();
      final session = DefaultPlaybackSessionService(audio);
      addTearDown(session.dispose);
      await session.setQueue([projectItem(asset: withBacking)]);
      audio.state = audio.state.copyWith(
        currentSource: AudioSourceType.instrumental,
      );
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: withBacking,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(
        session.currentState.currentItem!.audioAsset.instrumentalPath,
        '/old.wav',
      );
      audio.state = audio.state.copyWith(
        currentSource: AudioSourceType.original,
      );
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: withBacking,
          replacement: oldAsset,
        ),
        isTrue,
      );
      expect(
        session.currentState.currentItem!.audioAsset.instrumentalPath,
        isNull,
      );
    },
  );

  test(
    'does not update while switching songs or when a different project is active',
    () async {
      final audio = _Audio();
      final session = DefaultPlaybackSessionService(audio);
      addTearDown(session.dispose);
      await session.setQueue([
        projectItem(),
        projectItem(id: 'other', projectId: 'other-project'),
      ]);
      final gate = Completer<void>();
      audio.loadGate = gate.future;
      final switching = session.playAt(1);
      await audio.loadStarted.future;
      expect(
        await session.updateActiveProjectSources(
          projectId: 'other-project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(audio.updateCalls, 0);
      gate.complete();
      await switching;
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(
        session.currentState.queue.first.audioAsset.instrumentalPath,
        isNull,
      );
    },
  );

  test(
    'remote item and unsupported backend never update project sources',
    () async {
      final audio = _Audio();
      final session = DefaultPlaybackSessionService(audio);
      addTearDown(session.dispose);
      await session.setQueue([
        projectItem(stream: Uri.parse('https://example.org/song')),
      ]);
      expect(
        await session.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
      expect(audio.updateCalls, 0);
      final unsupported = DefaultPlaybackSessionService(_UnsupportedAudio());
      addTearDown(unsupported.dispose);
      await unsupported.setQueue([projectItem()]);
      expect(
        await unsupported.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
    },
  );

  test('disposed session rejects a source update', () async {
    final audio = _Audio();
    final session = DefaultPlaybackSessionService(audio);
    await session.setQueue([projectItem()]);
    await session.dispose();
    expect(
      await session.updateActiveProjectSources(
        projectId: 'project',
        expected: oldAsset,
        replacement: newAsset,
      ),
      isFalse,
    );
    expect(audio.updateCalls, 0);
  });

  test(
    'decorators fail closed when the delegate lacks this capability',
    () async {
      final library = LibraryMetadataPlaybackSessionService(
        delegate: _NoCapability(),
        libraryRepository: _Library(),
      );
      final remote = RemoteRebindingPlaybackSessionService(
        delegate: library,
        resolver: _Resolver(),
      );
      addTearDown(remote.dispose);
      expect(
        await remote.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isFalse,
      );
    },
  );

  test(
    'capability is available through both production session decorators',
    () async {
      final audio = _Audio();
      final base = DefaultPlaybackSessionService(audio);
      final library = LibraryMetadataPlaybackSessionService(
        delegate: base,
        libraryRepository: _Library(),
      );
      final remote = RemoteRebindingPlaybackSessionService(
        delegate: library,
        resolver: _Resolver(),
      );
      addTearDown(remote.dispose);
      await remote.setQueue([projectItem()]);
      expect(
        await remote.updateActiveProjectSources(
          projectId: 'project',
          expected: oldAsset,
          replacement: newAsset,
        ),
        isTrue,
      );
      expect(
        remote.currentState.currentItem!.audioAsset.instrumentalPath,
        '/backing.wav',
      );
    },
  );
}

class _Audio extends Fake
    implements AudioPlayerService, ActiveProjectAudioSourceUpdater {
  PlaybackState state = const PlaybackState.idle();
  AudioAsset? asset;
  int updateCalls = 0,
      loadCalls = 0,
      playCalls = 0,
      pauseCalls = 0,
      seekCalls = 0;
  bool reject = false;
  Future<void>? loadGate;
  final loadStarted = Completer<void>();
  @override
  PlaybackState get currentState => state;
  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {
    loadCalls++;
    if (loadGate != null) {
      if (!loadStarted.isCompleted) loadStarted.complete();
      await loadGate;
    }
    asset = audioAsset;
    state = state.copyWith(
      currentSource: AudioSourceType.original,
      duration: const Duration(minutes: 3),
    );
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    asset = null;
  }

  @override
  bool updateActiveProjectAudioSources({
    required AudioAsset expected,
    required AudioAsset replacement,
  }) {
    updateCalls++;
    if (reject) return false;
    final next = safeProjectAudioSourceUpdate(
      current: asset,
      expected: expected,
      replacement: replacement,
      activeSource: state.currentSource,
    );
    if (next == null) return false;
    asset = next;
    return true;
  }

  @override
  Future<void> play() async {
    playCalls++;
    state = state.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(isPlaying: false);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    state = state.copyWith(position: position);
  }
}

class _UnsupportedAudio extends Fake implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();
  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}
  @override
  Future<void> play() async {}
}

class _Store extends Fake implements PlaybackSessionStore {
  PlaybackSessionSnapshot? saved;
  @override
  Future<PlaybackSessionSnapshot?> load() async => null;
  @override
  Future<void> save(PlaybackSessionSnapshot snapshot) async {
    saved = snapshot;
  }
}

class _NoCapability extends Fake implements PlaybackSessionService {
  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

class _Library extends Fake implements LocalMediaLibraryRepository {}

class _Resolver extends Fake implements RemotePlaybackItemResolver {}
