import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/transfer_entry.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_brand_mark.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/features/home/presentation/dashboard_dependencies.dart';
import 'package:lyric_forge_ktv/features/home/presentation/screens/dashboard_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';

void main() {
  late _TestProjectRepository projects;
  late _TestPlayHistoryRepository history;
  late _TestPlaybackSessionService playbackSession;
  late _TestAudioPlayerService audioPlayer;
  late _TestTranscriptionQueue transcriptionQueue;
  late _TestTranscriptionSettingsStore transcriptionSettingsStore;
  late List<RouteSettings> pushed;

  setUp(() {
    projects = _TestProjectRepository();
    history = _TestPlayHistoryRepository();
    playbackSession = _TestPlaybackSessionService();
    audioPlayer = _TestAudioPlayerService();
    transcriptionQueue = _TestTranscriptionQueue();
    transcriptionSettingsStore = _TestTranscriptionSettingsStore();
    pushed = [];
  });

  Widget buildScreen() => MaterialApp(
    onGenerateRoute: (settings) {
      pushed.add(settings);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(body: Text('pushed page')),
      );
    },
    home: DashboardScreen(
      dependencies: DashboardDependencies(
        projectRepository: projects,
        playHistoryRepository: history,
        playbackSession: playbackSession,
        audioPlayer: audioPlayer,
        transcriptionQueue: transcriptionQueue,
        transcriptionSettingsStore: transcriptionSettingsStore,
        configDialogDependencies: TranscriptionConfigDialogDependencies(
          profileResolver: _UnusedTranscriptionProfileResolver(),
          downloadConnectionChecker: _UnusedAsrDownloadConnectionChecker(),
          downloadProxyStore: _UnusedDownloadProxyStore(),
        ),
      ),
    ),
  );

  testWidgets('shows empty states for playback history and projects', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('还没有播放记录'), findsOneWidget);
    expect(find.text('还没有歌词工程'), findsOneWidget);
    expect(find.text('打开一首本地音乐后，会从这里快速继续。'), findsOneWidget);
    expect(projects.calls, 1);
    expect(history.calls, 1);
    // Both shelves use the shared inline empty state.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppEmptyState &&
            widget.density == AppEmptyStateDensity.inline,
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('the header repeats the brand mark only without a rail', (
    WidgetTester tester,
  ) async {
    // The default 800-wide test window has no navigation rail, so the
    // header is the only place for the mark.
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.byType(AppBrandMark), findsOneWidget);
    expect(find.text('Elysium Player'), findsOneWidget);

    // A desktop window shows the mark at the top of the rail instead.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.byType(AppBrandMark), findsNothing);
    expect(find.text('Elysium Player'), findsOneWidget);
  });

  testWidgets('nothing playing: the hero is the only way to open music', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('选择音乐开始播放'), findsOneWidget);
    expect(find.text('打开音乐'), findsNothing);
    expect(find.text('选择音乐'), findsNothing);
    // The project shelf keeps its own action.
    expect(find.widgetWithText(TextButton, '批量导入'), findsOneWidget);
  });

  testWidgets('while playing, the header offers to open other music', (
    WidgetTester tester,
  ) async {
    playbackSession.state = const PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: 'song',
          title: '正在播放的歌',
          audioAsset: AudioAsset(
            originalPath: '/music/song.mp3',
            format: 'mp3',
          ),
        ),
      ],
      currentIndex: 0,
    );
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('选择音乐开始播放'), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard:header-open-music')),
      findsOneWidget,
    );
    expect(find.text('打开音乐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed shelves use the error colour, empty ones stay muted', (
    WidgetTester tester,
  ) async {
    projects.failuresRemaining = 1;
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final failed = tester.widget<AppEmptyState>(
      find.ancestor(
        of: find.text('最近工程加载失败'),
        matching: find.byType(AppEmptyState),
      ),
    );
    final empty = tester.widget<AppEmptyState>(
      find.ancestor(
        of: find.text('还没有播放记录'),
        matching: find.byType(AppEmptyState),
      ),
    );
    expect(failed.iconColor, AppColors.error);
    expect(empty.iconColor, isNull);
  });

  testWidgets('history read failure is not presented as an empty history', (
    WidgetTester tester,
  ) async {
    history.failuresRemaining = 2;
    history.items = [
      PlayHistory(
        id: 'song',
        name: 'Recovered song',
        filePath: '/music/song.mp3',
        playedAt: DateTime(2026),
      ),
    ];
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('播放记录加载失败'), findsOneWidget);
    expect(find.text('播放记录暂时无法读取，可以重新加载一次。'), findsOneWidget);
    expect(find.text('还没有播放记录'), findsNothing);
    expect(find.text('还没有歌词工程'), findsOneWidget);
    expect(history.calls, 1);

    for (var attempt = 0; attempt < 2; attempt++) {
      final retryButton = find.widgetWithText(OutlinedButton, '重试');
      await tester.ensureVisible(retryButton);
      await tester.pumpAndSettle();
      await tester.tap(retryButton);
      await tester.pumpAndSettle();
      if (attempt == 0) {
        expect(find.text('播放记录加载失败'), findsOneWidget);
        expect(find.text('还没有播放记录'), findsNothing);
      }
    }

    expect(history.calls, 3);
    expect(projects.calls, 3);
    expect(find.text('播放记录加载失败'), findsNothing);
    expect(find.text('还没有播放记录'), findsNothing);
    expect(find.text('Recovered song'), findsOneWidget);
    expect(find.text('还没有歌词工程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh observes immediate failures from both repositories', (
    WidgetTester tester,
  ) async {
    projects.failuresRemaining = 2;
    history.failuresRemaining = 2;
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.text('播放记录加载失败'), findsOneWidget);
    expect(find.text('最近工程加载失败'), findsOneWidget);

    for (var attempt = 0; attempt < 2; attempt++) {
      final retryButton = find.widgetWithText(OutlinedButton, '重试').first;
      await tester.ensureVisible(retryButton);
      await tester.pumpAndSettle();
      await tester.tap(retryButton);
      await tester.pumpAndSettle();
    }

    expect(projects.calls, 3);
    expect(history.calls, 3);
    expect(find.text('播放记录加载失败'), findsNothing);
    expect(find.text('最近工程加载失败'), findsNothing);
    expect(find.text('还没有播放记录'), findsOneWidget);
    expect(find.text('还没有歌词工程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries recent-project loading after an error', (
    WidgetTester tester,
  ) async {
    projects.failuresRemaining = 1;

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('最近工程加载失败'), findsOneWidget);
    expect(find.text('工程文件暂时无法读取，可以重新加载一次。'), findsOneWidget);
    expect(projects.calls, 1);

    final retryButton = find.widgetWithText(OutlinedButton, '重试');
    await tester.ensureVisible(retryButton);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(find.text('最近工程加载失败'), findsNothing);
    expect(find.text('还没有歌词工程'), findsOneWidget);
    expect(projects.calls, 2);
  });

  group('player entries (audit N-01)', () {
    const local = PlaybackItem(
      id: 'local',
      title: '本地歌曲',
      audioAsset: AudioAsset(originalPath: '/music/local.mp3', format: 'mp3'),
    );

    void playing(PlaybackItem item) {
      playbackSession.state = PlaybackSessionState(
        queue: [item],
        currentIndex: 0,
      );
    }

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('打开音乐 opens the library, not a player', (tester) async {
      playing(local);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(
        tester,
        find.byKey(const ValueKey('dashboard:header-open-music')),
      );

      expect([for (final route in pushed) route.name], ['/library']);
    });

    testWidgets('the idle hero opens the library', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('选择音乐开始播放'));

      expect([for (final route in pushed) route.name], ['/library']);
    });

    testWidgets('the hero opens the local player for a local song', (
      tester,
    ) async {
      playing(local);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('打开播放器'));

      expect([for (final route in pushed) route.name], ['/quick-play']);
    });

    testWidgets('the hero opens now playing for a desktop stream', (
      tester,
    ) async {
      final remote = local.copyWith(
        id: 'remote',
        streamUri: Uri.parse('http://192.168.1.2:8080/song'),
      );
      playing(remote);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('打开播放器'));

      expect([for (final route in pushed) route.name], ['/now-playing']);
    });

    testWidgets('the hero opens the project player for a project song', (
      tester,
    ) async {
      playing(local.copyWith(id: 'project-song', projectId: 'p1'));
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('打开歌词播放器'));

      expect([for (final route in pushed) route.name], ['/project/p1/player']);
    });

    testWidgets('a recent song resumes in the local player', (tester) async {
      final entry = PlayHistory(
        id: 'recent',
        name: '最近听过的歌',
        filePath: '/music/recent.mp3',
        playedAt: DateTime(2026),
      );
      history.items = [entry];
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tapAndSettle(tester, find.text('最近听过的歌'));

      expect(pushed, hasLength(1));
      expect(pushed.single.name, '/quick-play');
      expect(pushed.single.arguments, same(entry));
    });
  });

  group('transfer entry (audit L-02)', () {
    Future<void> openMoreMenu(WidgetTester tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
    }

    testWidgets('the header has no separate remote library button', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byTooltip('远程音乐库'), findsNothing);
      expect(find.byIcon(Icons.cast_connected_rounded), findsNothing);
      expect(find.byTooltip(TransferEntry.label), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('更多 lists 跨设备传输 first', (tester) async {
      await openMoreMenu(tester);

      final menu = find.byType(PopupMenuItem<String>);
      final values = [
        for (final item in tester.widgetList<PopupMenuItem<String>>(menu))
          item.value,
      ];
      expect(values, [TransferEntry.menuValue, 'modelSettings', 'settings']);
      expect(find.text(TransferEntry.label), findsOneWidget);
      expect(find.byIcon(TransferEntry.icon), findsOneWidget);
    });

    testWidgets('a phone opens the connect screen from 更多', (tester) async {
      await openMoreMenu(tester);
      await tester.tap(find.text(TransferEntry.label));
      await tester.pumpAndSettle();

      expect([for (final route in pushed) route.name], ['/remote-library']);
    });

    testWidgets('a desktop opens the sharing screen from 更多', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await openMoreMenu(tester);
      await tester.tap(find.text(TransferEntry.label));
      await tester.pumpAndSettle();

      expect([for (final route in pushed) route.name], ['/media-sharing']);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _TestProjectRepository implements ProjectRepository {
  int calls = 0;
  int failuresRemaining = 0;

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async {
    calls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('fixture read failure');
    }
    return const <ProjectManifest>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlayHistoryRepository implements PlayHistoryRepository {
  int calls = 0;
  int failuresRemaining = 0;
  List<PlayHistory> items = const [];

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    calls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('fixture history read failure');
    }
    return items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlaybackSessionService implements PlaybackSessionService {
  PlaybackSessionState state = const PlaybackSessionState();

  @override
  PlaybackSessionState get currentState => state;

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Stream<PlaybackSessionState> get stateStream =>
      const Stream<PlaybackSessionState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAudioPlayerService implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => const Stream<PlaybackState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTranscriptionQueue implements BatchTranscriptionQueue {
  static const _snapshot = TranscriptionQueueSnapshot(
    items: <TranscriptionQueueItem>[],
    isPaused: false,
    isProcessing: false,
  );

  @override
  TranscriptionQueueSnapshot get current => _snapshot;

  @override
  Stream<TranscriptionQueueSnapshot> get snapshots =>
      const Stream<TranscriptionQueueSnapshot>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTranscriptionSettingsStore implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async => null;

  @override
  Future<void> save(TranscriptionConfig config) async {}

  @override
  Future<void> clear() async {}
}

class _UnusedTranscriptionProfileResolver
    implements TranscriptionProfileResolver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAsrDownloadConnectionChecker
    implements AsrDownloadConnectionChecker {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedDownloadProxyStore implements TranscriptionDownloadProxyStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
