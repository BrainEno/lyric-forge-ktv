import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/mobile_getting_started.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/presentation/listen_home_guide.dart';

final _added = DateTime(2026, 11, 1);

LocalMediaLibraryEntry _entry(String path, {bool missing = false}) =>
    LocalMediaLibraryEntry(
      sourcePath: path,
      format: 'mp3',
      addedAt: _added,
      lastSeenAt: _added,
      isMissing: missing,
    );

LocalMediaMetadata _linked(String path) => LocalMediaMetadata(
  sourcePath: path,
  updatedAt: _added,
  metadata: const {'linkedProjectId': 'lyrics-1'},
);

PlayHistory _played(String path) => PlayHistory(
  id: 'h-$path',
  name: '晴天',
  filePath: path,
  playedAt: DateTime(2026, 11, 18, 9),
);

/// A store whose saves fail, as a full disk would.
class _FailingStore implements GettingStartedStore {
  _FailingStore(this.saved);

  final GettingStartedPreferences? saved;

  @override
  Future<GettingStartedPreferences?> load() async => saved;

  @override
  Future<void> save(GettingStartedPreferences preferences) async =>
      throw const FileSystemException('disk full');
}

void main() {
  late Directory music;
  late String qingtian;
  late String daoxiang;

  setUpAll(() {
    music = Directory.systemTemp.createTempSync('listen_home_guide_test');
    String song(String name) {
      final file = File('${music.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [0]);
      return file.path;
    }

    qingtian = song('qingtian.mp3');
    daoxiang = song('daoxiang.mp3');
  });

  tearDownAll(() => music.deleteSync(recursive: true));

  group('progressFrom', () {
    test('counts songs that are there and songs with lyrics', () {
      final progress = ListenHomeGuide.progressFrom(
        entries: [
          _entry(qingtian),
          _entry(daoxiang),
          _entry('/gone.mp3', missing: true),
        ],
        overrides: [_linked(qingtian)],
        histories: const [],
      );

      expect(progress.songCount, 2);
      expect(progress.lyricSongCount, 1);
      expect(progress.lyricSong?.audioAsset.originalPath, qingtian);
      expect(progress.playedWithLyrics, isFalse);
      expect(
        progress.stateOf(MobileGettingStartedStep.playWithLyrics),
        GettingStartedStepState.ready,
      );
    });

    test('only a play of a song with lyrics ticks the last step', () {
      MobileGettingStartedProgress after(String played) =>
          ListenHomeGuide.progressFrom(
            entries: [_entry(qingtian), _entry(daoxiang)],
            overrides: [_linked(qingtian)],
            histories: [_played(played)],
          );

      expect(after(daoxiang).playedWithLyrics, isFalse);
      expect(after(qingtian).playedWithLyrics, isTrue);
      expect(after(qingtian).allDone, isTrue);
    });
  });

  group('load', () {
    test('without a store the card never shows', () async {
      final guide = ListenHomeGuide(readOverrides: () async => const []);

      expect(await guide.load(entries: const [], histories: const []), isNull);
    });

    test('decides once: an empty library gets the card', () async {
      final store = MemoryGettingStartedStore();
      final guide = ListenHomeGuide(
        store: store,
        readOverrides: () async => const [],
      );

      final progress = await guide.load(entries: const [], histories: const []);

      expect(progress?.songCount, 0);
      expect(store.saved?.visibility, GettingStartedVisibility.active);
      expect(guide.preferences.visibility, GettingStartedVisibility.active);
    });

    test('someone who already has songs does not get it', () async {
      final store = MemoryGettingStartedStore();
      var overridesRead = false;
      final guide = ListenHomeGuide(
        store: store,
        readOverrides: () async {
          overridesRead = true;
          return const [];
        },
      );

      final progress = await guide.load(
        entries: [_entry(qingtian)],
        histories: const [],
      );

      expect(progress, isNull);
      expect(store.saved?.visibility, GettingStartedVisibility.dismissed);
      expect(overridesRead, isFalse);
    });

    test('a failing read hides the card instead of throwing', () async {
      final guide = ListenHomeGuide(
        store: MemoryGettingStartedStore(const GettingStartedPreferences()),
        readOverrides: () async => throw StateError('broken'),
      );

      expect(await guide.load(entries: const [], histories: const []), isNull);
    });
  });

  group('remember', () {
    test('saves the new visibility', () async {
      final store = MemoryGettingStartedStore();
      final guide = ListenHomeGuide(
        store: store,
        readOverrides: () async => const [],
      );
      await guide.load(entries: const [], histories: const []);

      await guide.remember(GettingStartedVisibility.completed);

      expect(store.saved?.visibility, GettingStartedVisibility.completed);
    });

    test('keeps the choice in memory when saving fails', () async {
      final guide = ListenHomeGuide(
        store: _FailingStore(null),
        readOverrides: () async => const [],
      );

      await guide.remember(GettingStartedVisibility.dismissed);

      expect(guide.preferences.visibility, GettingStartedVisibility.dismissed);
    });
  });
}
