import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_library_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/local_media_relink_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_file_names.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_availability.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/local_library_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/mobile_lyrics_screen.dart';

final _added = DateTime(2026, 11, 1);

LocalMediaLibraryEntry _entry(
  String path, {
  String? title,
  bool missing = false,
}) => LocalMediaLibraryEntry(
  sourcePath: path,
  format: 'mp3',
  addedAt: _added,
  lastSeenAt: _added,
  isMissing: missing,
  embeddedTitle: title,
);

LocalMediaMetadata _linked(String path, {String? title}) => LocalMediaMetadata(
  sourcePath: path,
  title: title,
  updatedAt: _added,
  metadata: const {'linkedProjectId': 'project-1'},
);

/// Answers only what the page reads; everything else is never called.
class _Library implements LocalMediaLibraryRepository {
  _Library(this.entries);
  final List<LocalMediaLibraryEntry> entries;

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements LocalMediaMetadataRepository {
  _Metadata(this.items);
  final List<LocalMediaMetadata> items;

  @override
  Future<List<LocalMediaMetadata>> getAll() async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Collaborators the page never calls.
class _UnusedLocalMediaCollectionRepository implements LocalMediaCollectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlayHistoryRepository implements PlayHistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedLocalMediaRelinkService implements LocalMediaRelinkService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAudioLibraryImportService implements AudioLibraryImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlaybackSessionService implements PlaybackSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAudioPlayerService implements AudioPlayerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedLyricFileImportService implements LyricFileImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlaybackLyricsResolver implements PlaybackLyricsResolver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalLibraryDependencies _dependencies({
  required List<LocalMediaLibraryEntry> entries,
  List<LocalMediaMetadata> metadata = const [],
}) {
  return LocalLibraryDependencies(
    libraryRepository: _Library(entries),
    collectionRepository: _UnusedLocalMediaCollectionRepository(),
    metadataRepository: _Metadata(metadata),
    playHistoryRepository: _UnusedPlayHistoryRepository(),
    relinkService: _UnusedLocalMediaRelinkService(),
    libraryImportService: _UnusedAudioLibraryImportService(),
    playbackSession: _UnusedPlaybackSessionService(),
    audioPlayer: _UnusedAudioPlayerService(),
    lyricsImport: LyricsImportDependencies(
      lyricsResolver: _UnusedPlaybackLyricsResolver(),
      importer: _UnusedLyricFileImportService(),
    ),
  );
}

Future<void> _pump(WidgetTester tester, LocalLibraryDependencies deps) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MobileLyricsScreen(dependencies: deps),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(body: Text('page ${settings.name}')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MobileLyricsSong.from', () {
    test('keeps playable songs, sorted by the title shown', () {
      final songs = MobileLyricsSong.from(
        [
          _entry('/m/b.mp3', title: '稻香'),
          _entry('/m/a.mp3', title: 'Apple'),
          _entry('/m/gone.mp3', title: '不在了'),
          _entry('/m/missing.mp3', title: '缺失', missing: true),
        ],
        const [],
        exists: (path) => path != '/m/gone.mp3',
      );

      expect(songs.map((song) => song.title), ['Apple', '稻香']);
    });

    test('applies the user title and reads the lyric link', () {
      final songs = MobileLyricsSong.from(
        [_entry('/m/a.mp3', title: 'tag')],
        [_linked('/m/a.mp3', title: '晴天')],
        exists: (_) => true,
      );

      expect(songs.single.title, '晴天');
      expect(songs.single.hasLyrics, isTrue);
      expect(songs.single.playbackItem.hasLyrics, isTrue);
      expect(songs.single.playbackItem.id, 'local:/m/a.mp3');
    });

    test('a picker-made file name is shown as 未命名歌曲', () {
      final songs = MobileLyricsSong.from(
        [
          _entry(
            '/m/image_20312602-F017-4D87-A99C-F527F145A697_1795329754.m4a',
          ),
        ],
        const [],
        exists: (_) => true,
      );

      expect(songs.single.title, untitledSongTitle);
    });
  });

  group('MobileLyricsScreen', () {
    testWidgets('offers transfer and no recognition', (tester) async {
      await _pump(tester, _dependencies(entries: const []));

      expect(find.text(MobileLyricsScreen.title), findsOneWidget);
      expect(find.text(MobileLyricsScreen.transferTitle), findsOneWidget);
      expect(find.textContaining('识别'), findsNothing);
      expect(find.textContaining('工程'), findsNothing);

      await tester.tap(find.byKey(MobileLyricsScreen.transferKey));
      await tester.pumpAndSettle();
      // Widget tests run as a desktop: the transfer entry picks its route.
      expect(find.textContaining('page '), findsOneWidget);
    });

    testWidgets('an empty library points to the library', (tester) async {
      await _pump(tester, _dependencies(entries: const []));

      expect(find.text('音乐库里还没有歌曲'), findsOneWidget);
      await tester.tap(find.text('去音乐库'));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.library}'), findsOneWidget);
    });

    testWidgets('lists songs without lyrics first', (tester) async {
      final music = Directory.systemTemp.createTempSync('mobile_lyrics_test');
      addTearDown(() => music.deleteSync(recursive: true));
      String song(String name) {
        final file = File('${music.path}${Platform.pathSeparator}$name')
          ..writeAsBytesSync(const [0]);
        return file.path;
      }

      final qingtian = song('a.mp3');
      final daoxiang = song('b.mp3');
      await _pump(
        tester,
        _dependencies(
          entries: [
            _entry(qingtian, title: '晴天'),
            _entry(daoxiang, title: '稻香'),
          ],
          metadata: [_linked(daoxiang)],
        ),
      );

      expect(find.text('${MobileLyricsScreen.missingTitle} · 1'), findsOneWidget);
      expect(find.text('${MobileLyricsScreen.pairedTitle} · 1'), findsOneWidget);
      final missingY = tester.getCenter(find.text('晴天')).dy;
      final pairedY = tester.getCenter(find.text('稻香')).dy;
      expect(missingY, lessThan(pairedY));
      // Only the song without lyrics carries the add button.
      expect(find.byTooltip(MobileLyricsScreen.addLyricsHint), findsOneWidget);
    });
  });
}
