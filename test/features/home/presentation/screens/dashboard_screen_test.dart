import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/transfer_entry.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started_store.dart';
import 'package:lyric_forge_ktv/features/home/domain/models/getting_started.dart';
import 'package:lyric_forge_ktv/features/home/presentation/dashboard_dependencies.dart';
import 'package:lyric_forge_ktv/features/home/presentation/screens/dashboard_screen.dart';
import 'package:lyric_forge_ktv/features/home/presentation/widgets/dashboard_getting_started_card.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_review_overview.dart';
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
  GettingStartedStore? guideStore;
  ProjectLyricReviewCounter? reviewCounter;

  setUp(() {
    projects = _TestProjectRepository();
    history = _TestPlayHistoryRepository();
    playbackSession = _TestPlaybackSessionService();
    audioPlayer = _TestAudioPlayerService();
    transcriptionQueue = _TestTranscriptionQueue();
    transcriptionSettingsStore = _TestTranscriptionSettingsStore();
    pushed = [];
    guideStore = null;
    reviewCounter = null;
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
        gettingStartedStore: guideStore,
        reviewCounter: reviewCounter,
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

  testWidgets('the header shows the name without a brand mark', (
    WidgetTester tester,
  ) async {
    // D-049: the embedded mark was removed; narrow and wide windows both
    // show the product name alone.
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.text('Elysium Player'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Elysium Player'),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
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
    // The project shelf leads to every project (D-063).
    expect(find.widgetWithText(TextButton, '全部工程'), findsOneWidget);
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

  group('开始使用 checklist (D-070)', () {
    ProjectManifest project(String id, {bool lyrics = false}) =>
        ProjectManifest(
          id: id,
          name: '晴天',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          lyricDocument: lyrics
              ? const LyricDocument(
                  language: 'zh',
                  lines: [
                    LyricLine(
                      text: '故事的小黄花',
                      startTime: Duration.zero,
                      endTime: Duration(seconds: 3),
                    ),
                  ],
                )
              : null,
        );

    ProjectLyricReviewCounter reviewedLines(int count) =>
        (_) => ProjectLyricReviewOverview(
          suggested: 1,
          mustCheck: 0,
          reviewed: count,
        );

    Finder action(GettingStartedStep step) =>
        find.byKey(DashboardGettingStartedCard.actionKey(step));

    testWidgets('a new user sees it and starts by importing', (tester) async {
      final store = MemoryGettingStartedStore();
      guideStore = store;
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardGettingStartedCard.cardKey), findsOneWidget);
      expect(find.text(GettingStartedText.title), findsOneWidget);
      expect(find.text(GettingStartedText.progress(0, 3)), findsOneWidget);
      expect(store.saved?.visibility, GettingStartedVisibility.active);
      // Only the first step has a button until there are lyrics.
      expect(action(GettingStartedStep.reviewLyrics), findsNothing);
      expect(action(GettingStartedStep.singKtv), findsNothing);
      expect(find.text(GettingStartedText.lockedDetail), findsNWidgets(2));

      await tester.tap(action(GettingStartedStep.importSong));
      await tester.pumpAndSettle();

      expect(pushed.last.name, Routes.import);
    });

    testWidgets('someone who already has projects does not see it', (
      tester,
    ) async {
      final store = MemoryGettingStartedStore();
      guideStore = store;
      projects.items = [project('a', lyrics: true)];
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardGettingStartedCard.cardKey), findsNothing);
      expect(store.saved?.visibility, GettingStartedVisibility.dismissed);
    });

    testWidgets('while recognising, the first step shows the progress', (
      tester,
    ) async {
      guideStore = MemoryGettingStartedStore(
        const GettingStartedPreferences(
          visibility: GettingStartedVisibility.active,
        ),
      );
      projects.items = [project('a')];
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('正在识别「晴天」'), findsOneWidget);
      expect(
        find.descendant(
          of: action(GettingStartedStep.importSong),
          matching: find.text('查看进度'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with lyrics, review and KTV go to that project', (
      tester,
    ) async {
      final store = MemoryGettingStartedStore(
        const GettingStartedPreferences(
          visibility: GettingStartedVisibility.active,
        ),
      );
      guideStore = store;
      reviewCounter = reviewedLines(0);
      projects.items = [project('p1', lyrics: true)];
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text(GettingStartedText.progress(1, 3)), findsOneWidget);
      expect(action(GettingStartedStep.importSong), findsNothing);
      // The next step is the filled button, the later one outlined.
      expect(
        find.descendant(
          of: find.byKey(
            DashboardGettingStartedCard.stepKey(
              GettingStartedStep.reviewLyrics,
            ),
          ),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      await tester.tap(action(GettingStartedStep.reviewLyrics));
      await tester.pumpAndSettle();
      expect(pushed.last.name, Routes.lyricEditorPath('p1'));

      Navigator.of(tester.element(find.text('pushed page'))).pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(action(GettingStartedStep.singKtv));
      await tester.pumpAndSettle();
      await tester.tap(action(GettingStartedStep.singKtv));
      await tester.pumpAndSettle();
      expect(pushed.last.name, Routes.playerPath('p1'));
      expect(store.saved?.openedKtv, isTrue);
    });

    testWidgets('closing it offers an undo', (tester) async {
      final store = MemoryGettingStartedStore();
      guideStore = store;
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(DashboardGettingStartedCard.dismissKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardGettingStartedCard.cardKey), findsNothing);
      expect(store.saved?.visibility, GettingStartedVisibility.dismissed);
      expect(find.text(GettingStartedText.dismissedNotice), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardGettingStartedCard.cardKey), findsOneWidget);
      expect(store.saved?.visibility, GettingStartedVisibility.active);
    });

    testWidgets('after all three steps it can be put away', (tester) async {
      final store = MemoryGettingStartedStore(
        const GettingStartedPreferences(
          visibility: GettingStartedVisibility.active,
          openedKtv: true,
        ),
      );
      guideStore = store;
      reviewCounter = reviewedLines(2);
      projects.items = [project('p1', lyrics: true)];
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text(GettingStartedText.doneTitle), findsOneWidget);
      expect(find.text(GettingStartedText.progress(3, 3)), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(DashboardGettingStartedCard.finishKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(DashboardGettingStartedCard.finishKey));
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardGettingStartedCard.cardKey), findsNothing);
      expect(store.saved?.visibility, GettingStartedVisibility.completed);
    });

    testWidgets('a step reads as one sentence to a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      guideStore = MemoryGettingStartedStore();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'^第 1 步，导入一首歌，自动识别歌词，可以开始。')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}

class _TestProjectRepository implements ProjectRepository {
  int calls = 0;
  int failuresRemaining = 0;
  List<ProjectManifest> items = const [];

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async {
    calls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('fixture read failure');
    }
    return items;
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
