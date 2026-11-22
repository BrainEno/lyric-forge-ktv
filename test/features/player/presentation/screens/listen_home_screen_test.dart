import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/widgets/app_song_row.dart';
import 'package:lyric_forge_ktv/core/widgets/app_vinyl_disc.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_library_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/local_media_relink_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_availability.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/local_library_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/listen_home_screen.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

final _added = DateTime(2026, 11, 1);

LocalMediaLibraryEntry _entry(
  String path, {
  String? title,
  String? artist,
  bool missing = false,
}) => LocalMediaLibraryEntry(
  sourcePath: path,
  format: 'mp3',
  addedAt: _added,
  lastSeenAt: _added,
  isMissing: missing,
  embeddedTitle: title,
  embeddedArtist: artist,
);

PlayHistory _history(
  String id,
  String path, {
  required int minute,
  String name = '晴天',
  String? artist,
  Duration? position,
}) => PlayHistory(
  id: id,
  name: name,
  artist: artist,
  filePath: path,
  playedAt: DateTime(2026, 11, 18, 9, minute),
  lastPosition: position,
);

PlaybackItem _localItem(
  String path, {
  String title = '晴天',
  bool lyrics = false,
}) => PlaybackItem(
  id: 'local:$path',
  title: title,
  artist: '周杰伦',
  hasLyrics: lyrics,
  audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
);

PlaybackState _audio({bool playing = false}) => PlaybackState(
  isPlaying: playing,
  isBuffering: false,
  isCompleted: false,
  isLoading: false,
  position: const Duration(seconds: 30),
  duration: const Duration(minutes: 4),
  bufferedPosition: Duration.zero,
  speed: 1,
  volume: 1,
);

void main() {
  late Directory music;
  late String qingtian;
  late String daoxiang;
  late String anjing;

  setUpAll(() {
    music = Directory.systemTemp.createTempSync('listen_home_test');
    String song(String name) {
      final file = File('${music.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(const [0]);
      return file.path;
    }

    qingtian = song('qingtian.mp3');
    daoxiang = song('daoxiang.mp3');
    anjing = song('anjing.mp3');
  });

  tearDownAll(() => music.deleteSync(recursive: true));

  group('queueFrom', () {
    test('keeps songs whose file is there, sorted by title', () {
      final queue = ListenHomeScreen.queueFrom([
        _entry('/m/b.mp3', title: '稻香'),
        _entry('/m/a.mp3', title: 'Apple'),
        _entry('/m/c.mp3', title: 'banana'),
        _entry('/m/gone.mp3', title: '不在了'),
      ], exists: (path) => path != '/m/gone.mp3');

      expect(queue.map((item) => item.title), ['Apple', 'banana', '稻香']);
    });

    test('drops songs the library already knows are missing', () {
      final queue = ListenHomeScreen.queueFrom([
        _entry('/m/a.mp3', title: 'A', missing: true),
        _entry('/m/b.mp3', title: 'B'),
      ], exists: (_) => true);

      expect(queue.map((item) => item.title), ['B']);
    });

    test('checks the disk when no check is given', () {
      final queue = ListenHomeScreen.queueFrom([
        _entry(qingtian, title: '晴天'),
        _entry('${music.path}/not-there.mp3', title: '不在'),
      ]);

      expect(queue.single.audioAsset.originalPath, qingtian);
    });

    test('an empty library gives an empty queue', () {
      expect(ListenHomeScreen.queueFrom(const []), isEmpty);
    });
  });

  group('titleOf', () {
    test('prefers the tag', () {
      expect(ListenHomeScreen.titleOf(_entry('/m/x.mp3', title: ' 晴天 ')), '晴天');
    });

    test('falls back to the file name without its extension', () {
      expect(ListenHomeScreen.titleOf(_entry('/m/稻香.flac')), '稻香');
      expect(ListenHomeScreen.titleOf(_entry(r'C:\music\安静.mp3')), '安静');
      expect(ListenHomeScreen.titleOf(_entry('/m/.hidden')), '.hidden');
      expect(
        ListenHomeScreen.titleOf(_entry('/m/no-extension')),
        'no-extension',
      );
    });

    test('a blank tag counts as none', () {
      expect(ListenHomeScreen.titleOf(_entry('/m/晴天.mp3', title: '  ')), '晴天');
    });
  });

  group('itemFor', () {
    test('keys the song the way the library does', () {
      final entry = LocalMediaLibraryEntry(
        sourcePath: '/m/qingtian.flac',
        format: 'flac',
        addedAt: _added,
        lastSeenAt: _added,
        embeddedTitle: '晴天',
        embeddedArtist: '周杰伦',
        embeddedArtworkPath: '/covers/yehuimei.jpg',
      );

      final item = ListenHomeScreen.itemFor(entry);

      expect(item.id, 'local:/m/qingtian.flac');
      expect(item.title, '晴天');
      expect(item.artist, '周杰伦');
      expect(item.artworkPath, '/covers/yehuimei.jpg');
      expect(item.audioAsset.originalPath, '/m/qingtian.flac');
      expect(item.audioAsset.format, 'flac');
      expect(item.audioAsset.thumbnailPath, '/covers/yehuimei.jpg');
      expect(item.preferredSource, AudioSourceType.original);
      expect(item.projectId, isNull);
      expect(item.isRemoteStream, isFalse);
    });
  });

  group('distinctRecent', () {
    test('keeps the newest play of each file, newest first', () {
      final recent = ListenHomeScreen.distinctRecent([
        _history('1', '/m/a.mp3', minute: 1, name: 'A 旧'),
        _history('2', '/m/b.mp3', minute: 2, name: 'B'),
        _history('3', '/m/a.mp3', minute: 3, name: 'A 新'),
      ]);

      expect(recent.map((history) => history.name), ['A 新', 'B']);
    });

    test('stops at the limit', () {
      final recent = ListenHomeScreen.distinctRecent([
        for (var i = 0; i < 12; i++) _history('$i', '/m/$i.mp3', minute: i),
      ]);

      expect(recent, hasLength(ListenHomeScreen.recentLimit));
      expect(recent.first.id, '11');
      expect(
        ListenHomeScreen.distinctRecent([
          for (var i = 0; i < 5; i++) _history('$i', '/m/$i.mp3', minute: i),
        ], limit: 2),
        hasLength(2),
      );
    });

    test('treats one file spelled two ways as one song', () {
      final absolute = File('music/a.mp3').absolute.path;
      final recent = ListenHomeScreen.distinctRecent([
        _history('1', 'music/a.mp3', minute: 1),
        _history('2', absolute, minute: 2),
      ]);

      expect(recent.single.id, '2');
    });
  });

  group('the page', () {
    late _Session session;
    late _Audio audio;
    late _Library library;
    late _History history;
    late List<String> pushed;
    MediaImportService? mediaImport;

    setUp(() {
      mediaImport = null;
      session = _Session(const PlaybackSessionState());
      audio = _Audio(_audio());
      library = _Library([
        _entry(qingtian, title: '晴天', artist: '周杰伦'),
        _entry(daoxiang, title: '稻香', artist: '周杰伦'),
        _entry(anjing, title: '安静', artist: '周杰伦'),
        _entry('${music.path}/gone.mp3', title: '不在了', missing: true),
      ]);
      history = _History([
        _history('h1', qingtian, minute: 5, artist: '周杰伦'),
        _history(
          'h2',
          daoxiang,
          minute: 4,
          name: '稻香',
          position: const Duration(minutes: 1, seconds: 5),
        ),
      ]);
      pushed = [];
    });

    tearDown(() async {
      await session.close();
      await audio.close();
    });

    LocalLibraryDependencies dependencies() => LocalLibraryDependencies(
      libraryRepository: library,
      collectionRepository: _Collections(),
      metadataRepository: _Metadata(),
      playHistoryRepository: history,
      relinkService: _Relink(),
      libraryImportService: _LibraryImport(),
      playbackSession: session,
      audioPlayer: audio,
      lyricsImport: LyricsImportDependencies(
        lyricsResolver: _Resolver(),
        importer: _LyricImporter(),
      ),
      mediaImport: mediaImport,
    );

    Future<void> pumpHome(
      WidgetTester tester, {
      math.Random? random,
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ListenHomeScreen(dependencies: dependencies(), random: random),
          onGenerateRoute: (settings) {
            pushed.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('页面 ${settings.name}')),
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Finder heroText(String text) => find.descendant(
      of: find.byKey(ListenHomeScreen.heroKey),
      matching: find.text(text),
    );

    testWidgets('with nothing on, offers a still record and a way to start', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(heroText(ListenHomeScreen.idleTitle), findsOneWidget);
      expect(heroText('从 3 首本地歌曲里挑一首，或者随便听听。'), findsOneWidget);
      expect(find.text('离线播放 · 3 首本地歌曲'), findsOneWidget);
      final disc = tester.widget<AppVinylDisc>(
        find.descendant(
          of: find.byKey(ListenHomeScreen.heroKey),
          matching: find.byType(AppVinylDisc),
        ),
      );
      expect(disc.spinning, isFalse);
      expect(find.byKey(ListenHomeScreen.lyricsNudgeKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty library points to adding music', (tester) async {
      library = _Library(const []);
      history = _History(const []);
      await pumpHome(tester);

      expect(heroText('先把歌曲放进音乐库：添加手机里的音乐文件夹，或从电脑传过来。'), findsOneWidget);
      expect(heroText('从电脑传歌'), findsOneWidget);
      expect(find.text('播放过的歌曲会出现在这里。'), findsOneWidget);
      final playAll = tester.widget<ButtonStyleButton>(
        find.byKey(ListenHomeScreen.playAllKey),
      );
      expect(playAll.onPressed, isNull);
    });

    testWidgets('on a phone, an empty library leads with 导入音频或视频 (D-056)', (
      tester,
    ) async {
      library = _Library([]);
      history = _History(const []);
      final importer = _MediaImport(library, '${music.path}/新歌.m4a');
      mediaImport = importer;
      await pumpHome(tester);

      expect(
        heroText('先把歌曲放进音乐库：从“文件”或相册导入音频、视频，或从电脑传过来。'),
        findsOneWidget,
      );
      expect(find.byKey(ListenHomeScreen.importKey), findsOneWidget);
      await tester.tap(find.byKey(ListenHomeScreen.idleImportKey));
      await tester.pumpAndSettle();
      expect(find.text('从相册选择视频'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-import-source-photos')));
      await tester.pumpAndSettle();

      expect(importer.sources, [MediaImportSource.photoLibrary]);
      expect(find.text('已导入 1 首歌曲（其中 1 个视频已提取为音频）'), findsOneWidget);
      expect(find.text('离线播放 · 1 首本地歌曲'), findsOneWidget);
    });

    testWidgets('播放全部 queues every song there, by title', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byKey(ListenHomeScreen.playAllKey));
      await tester.pump();

      expect(session.queues, hasLength(1));
      expect(session.queues.single.map((item) => item.title), [
        '安静',
        '晴天',
        '稻香',
      ]);
    });

    testWidgets('随机播放 shuffles the same songs', (tester) async {
      await pumpHome(tester, random: math.Random(7));

      await tester.tap(find.byKey(ListenHomeScreen.shuffleKey));
      await tester.pump();

      final expected = ListenHomeScreen.queueFrom(library.entries)
        ..shuffle(math.Random(7));
      final queued = session.queues.single;
      expect(queued.map((item) => item.id), expected.map((item) => item.id));
      expect(queued.map((item) => item.title).toSet(), {'安静', '晴天', '稻香'});
    });

    testWidgets('says so when no file can be played', (tester) async {
      library = _Library([_entry('${music.path}/gone.mp3', title: '不在了')]);
      await pumpHome(tester);

      // The library lists it, but the file is not there.
      await tester.tap(find.byKey(ListenHomeScreen.playAllKey));
      await tester.pump();

      expect(session.queues, isEmpty);
      expect(find.text(ListenHomeScreen.noSongsMessage), findsOneWidget);
    });

    testWidgets('while a song plays, the record turns and the hero is it', (
      tester,
    ) async {
      session = _Session(
        PlaybackSessionState(
          queue: [
            _localItem(qingtian),
            _localItem(daoxiang, title: '稻香'),
          ],
          currentIndex: 0,
        ),
      );
      audio = _Audio(_audio(playing: true));
      await pumpHome(tester);

      expect(heroText('晴天'), findsOneWidget);
      expect(heroText(ListenHomeScreen.idleTitle), findsNothing);
      final disc = tester.widget<AppVinylDisc>(
        find.descendant(
          of: find.byKey(ListenHomeScreen.heroKey),
          matching: find.byType(AppVinylDisc),
        ),
      );
      expect(disc.spinning, isTrue);
      expect(disc.glow, isTrue);
      expect(find.byTooltip('上一首'), findsOneWidget);
      expect(find.byTooltip('下一首'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the transport drives the session', (tester) async {
      session = _Session(
        PlaybackSessionState(
          queue: [
            _localItem(qingtian),
            _localItem(daoxiang, title: '稻香'),
          ],
          currentIndex: 0,
        ),
      );
      audio = _Audio(_audio(playing: true));
      await pumpHome(tester);

      await tester.tap(find.byTooltip(TransportBar.pauseTooltip));
      await tester.pump();
      await tester.tap(find.byTooltip('下一首'));
      await tester.pump();

      expect(session.calls, ['togglePlayPause', 'skipNext']);
    });

    testWidgets('a song without lyrics gets an import nudge', (tester) async {
      session = _Session(
        PlaybackSessionState(queue: [_localItem(qingtian)], currentIndex: 0),
      );
      await pumpHome(tester);

      expect(find.byKey(ListenHomeScreen.lyricsNudgeKey), findsOneWidget);
      expect(find.text('「晴天」还没有歌词'), findsOneWidget);
      expect(find.text(ListenHomeScreen.importLyricsLabel), findsOneWidget);
    });

    testWidgets('a song with lyrics has no nudge', (tester) async {
      session = _Session(
        PlaybackSessionState(
          queue: [_localItem(qingtian, lyrics: true)],
          currentIndex: 0,
        ),
      );
      await pumpHome(tester);

      expect(find.byKey(ListenHomeScreen.lyricsNudgeKey), findsNothing);
    });

    testWidgets('a project song has no nudge, its lyrics live in the project', (
      tester,
    ) async {
      session = _Session(
        PlaybackSessionState(
          queue: [
            PlaybackItem(
              id: 'project:p1',
              title: '晴天',
              projectId: 'p1',
              audioAsset: AudioAsset(originalPath: qingtian, format: 'mp3'),
            ),
          ],
          currentIndex: 0,
        ),
      );
      await pumpHome(tester);

      expect(find.byKey(ListenHomeScreen.lyricsNudgeKey), findsNothing);
    });

    testWidgets('最近播放 lists each song once and marks the one playing', (
      tester,
    ) async {
      history = _History([
        _history('h1', qingtian, minute: 5, artist: '周杰伦'),
        _history('h0', qingtian, minute: 1, artist: '周杰伦'),
        _history(
          'h2',
          daoxiang,
          minute: 4,
          name: '稻香',
          position: const Duration(minutes: 1, seconds: 5),
        ),
      ]);
      session = _Session(
        PlaybackSessionState(queue: [_localItem(qingtian)], currentIndex: 0),
      );
      audio = _Audio(_audio(playing: true));
      await pumpHome(tester);

      expect(
        find.byKey(const ValueKey('listen-home:recent:h1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('listen-home:recent:h0')), findsNothing);
      final playing = tester.widget<AppSongRow>(
        find.byKey(const ValueKey('listen-home:recent:h1')),
      );
      final other = tester.widget<AppSongRow>(
        find.byKey(const ValueKey('listen-home:recent:h2')),
      );
      expect(playing.playback, AppSongRowPlayback.playing);
      expect(playing.subtitle, '周杰伦');
      expect(other.playback, AppSongRowPlayback.none);
      expect(other.subtitle, '本地音乐 · 听到 1:05');
    });

    testWidgets('a recent song resumes through the local player', (
      tester,
    ) async {
      await pumpHome(tester);
      final row = find.byKey(const ValueKey('listen-home:recent:h2'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(pushed, [Routes.quickPlay]);
      expect(history.reads, greaterThanOrEqualTo(1));
    });

    testWidgets('the library shortcuts open each section', (tester) async {
      await pumpHome(tester);
      final albums = find.text('专辑');
      await tester.scrollUntilVisible(
        albums,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(albums);
      await tester.pumpAndSettle();

      expect(pushed, [Routes.libraryAlbums]);
    });

    testWidgets('a new song refreshes 最近播放', (tester) async {
      await pumpHome(tester);
      final before = history.reads;

      session.emit(
        PlaybackSessionState(queue: [_localItem(anjing)], currentIndex: 0),
      );
      await tester.pump();
      await tester.pump();

      expect(history.reads, before + 1);

      // Play and pause of the same song read nothing.
      session.emit(
        PlaybackSessionState(queue: [_localItem(anjing)], currentIndex: 0),
      );
      await tester.pump();
      expect(history.reads, before + 1);
    });

    testWidgets('a library that cannot be read says so', (tester) async {
      library = _Library(const [], fail: true);
      await pumpHome(tester);

      expect(find.textContaining('library.json'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(320, 640),
      Size(390, 844),
      Size(820, 1180),
    ]) {
      testWidgets('fits a ${size.width.toInt()}-wide screen', (tester) async {
        session = _Session(
          PlaybackSessionState(
            queue: [_localItem(qingtian, title: '很长很长的歌名' * 6)],
            currentIndex: 0,
          ),
        );
        await pumpHome(tester, size: size);

        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the record reads as one button that opens the player', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      session = _Session(
        PlaybackSessionState(queue: [_localItem(qingtian)], currentIndex: 0),
      );
      await pumpHome(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^正在播放：晴天')),
      );
      expect(node.hint, ListenHomeScreen.openPlayerHint);

      await tester.tap(
        find.descendant(
          of: find.byKey(ListenHomeScreen.heroKey),
          matching: find.byType(AppVinylDisc),
        ),
      );
      await tester.pumpAndSettle();
      expect(pushed, [Routes.nowPlaying]);
      handle.dispose();
    });
  });
}

class _Session implements PlaybackSessionService {
  _Session(this.currentState);

  final _controller = StreamController<PlaybackSessionState>.broadcast();
  final queues = <List<PlaybackItem>>[];
  final calls = <String>[];

  @override
  PlaybackSessionState currentState;

  void emit(PlaybackSessionState state) {
    currentState = state;
    _controller.add(state);
  }

  Future<void> close() => _controller.close();

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    queues.add(List.of(items));
  }

  @override
  Future<void> togglePlayPause() async => calls.add('togglePlayPause');

  @override
  Future<void> skipNext() async => calls.add('skipNext');

  @override
  Future<void> skipPrevious() async => calls.add('skipPrevious');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements AudioPlayerService {
  _Audio(this.currentState);

  final _controller = StreamController<PlaybackState>.broadcast();

  @override
  PlaybackState currentState;

  Future<void> close() => _controller.close();

  @override
  Stream<PlaybackState> get stateStream => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library implements LocalMediaLibraryRepository {
  _Library(this.entries, {this.fail = false});

  final List<LocalMediaLibraryEntry> entries;
  final bool fail;

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async {
    if (fail) throw const FileSystemException('library.json');
    return entries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements PlayHistoryRepository {
  _History(this.histories);

  final List<PlayHistory> histories;
  int reads = 0;

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    reads++;
    return histories.take(limit).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Collections implements LocalMediaCollectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements LocalMediaMetadataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Relink implements LocalMediaRelinkService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LibraryImport implements AudioLibraryImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements PlaybackLyricsResolver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LyricImporter implements LyricFileImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaImport implements MediaImportService {
  _MediaImport(this.library, this.path);

  final _Library library;
  final String path;
  final sources = <MediaImportSource>[];

  @override
  bool get supportsPhotoLibrary => true;

  @override
  bool get supportsVideo => true;

  @override
  Future<MediaImportResult> importMedia(
    MediaImportSource source, {
    void Function(MediaImportProgress progress)? onProgress,
  }) async {
    sources.add(source);
    onProgress?.call(
      const MediaImportProgress(
        index: 0,
        total: 1,
        name: 'clip.mov',
        phase: MediaImportPhase.extracting,
      ),
    );
    File(path).writeAsBytesSync(const [0]);
    library.entries.add(_entry(path, title: '新歌'));
    return MediaImportResult(importedPaths: [path], extractedFromVideo: 1);
  }
}
