import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_library_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/local_media_relink_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_availability.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/local_library_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/global_player_bar.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/mobile_global_player_bar.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/player_bar_semantics.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

const _song = PlaybackItem(
  id: 'song',
  title: '晴天',
  artist: '周杰伦',
  projectId: 'project',
  audioAsset: AudioAsset(originalPath: '/music/qingtian.mp3', format: 'mp3'),
);

const _playing = PlaybackState(
  isPlaying: true,
  isBuffering: false,
  isCompleted: false,
  isLoading: false,
  position: Duration.zero,
  bufferedPosition: Duration.zero,
  speed: 1,
  volume: 1,
);

PlaybackState _with({bool playing = false, bool buffering = false}) =>
    PlaybackState(
      isPlaying: playing,
      isBuffering: buffering,
      isCompleted: false,
      isLoading: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1,
      volume: 1,
    );

void main() {
  group('labels', () {
    test('play button says what it does, or that audio is loading', () {
      expect(PlayerBarSemantics.playPause(_with()), TransportBar.playTooltip);
      expect(PlayerBarSemantics.playPause(_playing), TransportBar.pauseTooltip);
      expect(
        PlayerBarSemantics.playPause(_with(playing: true, buffering: true)),
        TransportBar.busyTooltip,
      );
      expect(PlayerBarSemantics.isBusy(_with(buffering: true)), isTrue);
      expect(PlayerBarSemantics.isBusy(_playing), isFalse);
    });

    test('now playing reads title and subtitle', () {
      expect(PlayerBarSemantics.nowPlaying('晴天', '周杰伦'), '正在播放：晴天，周杰伦');
      expect(PlayerBarSemantics.nowPlaying(' 晴天 ', ' '), '正在播放：晴天');
      expect(PlayerBarSemantics.nowPlaying('', '周杰伦'), '正在播放：未命名歌曲，周杰伦');
    });

    test('queue count is spoken with its unit', () {
      expect(PlayerBarSemantics.queue(0), '播放队列为空');
      expect(PlayerBarSemantics.queue(3), '播放队列，3 首');
    });

    test('subtitle prefers the artist, then the source', () {
      String subtitle(PlaybackItem item) => PlayerBarSemantics.subtitleFor(
        item,
        projectLabel: '歌词工程',
        remoteLabel: '远程音乐',
        localLabel: '本地音乐',
      );
      const asset = AudioAsset(originalPath: '/a.mp3', format: 'mp3');

      expect(subtitle(_song), '周杰伦');
      expect(
        subtitle(
          const PlaybackItem(
            id: 'p',
            title: 't',
            projectId: 'p',
            audioAsset: asset,
          ),
        ),
        '歌词工程',
      );
      expect(
        subtitle(
          PlaybackItem(
            id: 'r',
            title: 't',
            audioAsset: asset,
            streamUri: Uri.parse('http://192.168.1.2/a.mp3'),
          ),
        ),
        '远程音乐',
      );
      expect(
        subtitle(
          const PlaybackItem(
            id: 'l',
            title: 't',
            artist: ' ',
            audioAsset: asset,
          ),
        ),
        '本地音乐',
      );
    });
  });

  group('mobile bar', () {
    testWidgets('title block is one button that opens the full player', (
      tester,
    ) async {
      final routes = <String>[];
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(_mobileBar(), routes));

      expect(find.bySemanticsLabel('正在播放：晴天，周杰伦'), findsOneWidget);
      final target = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '正在播放：晴天，周杰伦',
        ),
      );
      expect(target.properties.hint, PlayerBarSemantics.openHint);
      expect(target.properties.button, isTrue);

      await tester.tap(find.text('晴天'));
      await tester.pumpAndSettle();
      expect(routes, ['/now-playing']);
      handle.dispose();
    });

    testWidgets('buffering disables play and says it is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_mobileBar(playback: _with(buffering: true)), <String>[]),
      );

      expect(find.byTooltip(TransportBar.busyTooltip), findsOneWidget);
      expect(find.byTooltip('播放'), findsNothing);
    });

    testWidgets('shows nothing without a current song', (tester) async {
      await tester.pumpWidget(
        _host(_mobileBar(session: const PlaybackSessionState()), <String>[]),
      );
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('desktop bar', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('artwork and title are read once, as one button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(_desktopBar(), <String>[]));

      expect(find.bySemanticsLabel('正在播放：晴天，周杰伦'), findsOneWidget);
      expect(find.byType(ExcludeSemantics), findsWidgets);
      handle.dispose();
    });

    testWidgets('queue toggle names the queue and its size', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(_desktopBar(), <String>[]));

      // Compact width shows only the number.
      final toggle = find.byKey(PlayerBarQueueToggle.toggleKey);
      expect(
        find.descendant(of: toggle, matching: find.text('1')),
        findsOneWidget,
      );
      Semantics semanticsOf() => tester.widget<Semantics>(
        find.ancestor(
          of: toggle,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == '播放队列，1 首',
          ),
        ),
      );
      expect(semanticsOf().properties.expanded, isFalse);
      expect(find.byTooltip(PlayerBarSemantics.queueTooltip), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(semanticsOf().properties.expanded, isTrue);
    });

    testWidgets('buffering uses the loading label with the shortcut', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(_desktopBar(playback: _with(buffering: true)), <String>[]),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              (widget.tooltip ?? '').startsWith(TransportBar.busyTooltip),
        ),
        findsOneWidget,
      );
    });
  });
}

Widget _host(Widget bar, List<String> routes) => MaterialApp(
  onGenerateRoute: (settings) {
    routes.add(settings.name ?? '');
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const Scaffold(body: Text('播放页')),
    );
  },
  home: Scaffold(bottomNavigationBar: bar),
);

Widget _mobileBar({
  PlaybackSessionState session = const PlaybackSessionState(
    queue: [_song],
    currentIndex: 0,
  ),
  PlaybackState playback = _playing,
}) => MobileGlobalPlayerBar(dependencies: _dependencies(session, playback));

Widget _desktopBar({PlaybackState playback = _playing}) => GlobalPlayerBar(
  dependencies: _dependencies(
    const PlaybackSessionState(queue: [_song], currentIndex: 0),
    playback,
  ),
);

LocalLibraryDependencies _dependencies(
  PlaybackSessionState session,
  PlaybackState playback,
) => LocalLibraryDependencies(
  libraryRepository: _Library(),
  collectionRepository: _Collections(),
  metadataRepository: _Metadata(),
  playHistoryRepository: _History(),
  relinkService: _Relink(),
  libraryImportService: _LibraryImport(),
  playbackSession: _Session(session),
  audioPlayer: _Audio(playback),
  lyricsImport: LyricsImportDependencies(
    lyricsResolver: _Resolver(),
    importer: _LyricImporter(),
  ),
);

class _Session implements PlaybackSessionService {
  _Session(this.currentState);

  @override
  final PlaybackSessionState currentState;

  @override
  Stream<PlaybackSessionState> get stateStream =>
      const Stream<PlaybackSessionState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements AudioPlayerService {
  _Audio(this.currentState);

  @override
  final PlaybackState currentState;

  @override
  Stream<PlaybackState> get stateStream => const Stream<PlaybackState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library implements LocalMediaLibraryRepository {
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

class _History implements PlayHistoryRepository {
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
