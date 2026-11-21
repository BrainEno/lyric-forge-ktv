import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_take_history_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/playback_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/player_screen.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_lyric_stage.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/player_lyric_semantics.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/reference_lyrics_view.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_timing.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

const _audio = AudioAsset(originalPath: '/song.mp3', format: 'mp3');

const _plainLines = [
  LyricLine(text: '第一句参考', startTime: Duration.zero, endTime: Duration.zero),
  LyricLine(text: '第二句参考', startTime: Duration.zero, endTime: Duration.zero),
];

ProjectManifest _project({LyricDocument? document}) => ProjectManifest(
  id: 'project',
  name: 'Song',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  audioAsset: _audio,
  lyricDocument: document,
);

PlaybackSessionState _state() => const PlaybackSessionState(
  queue: [
    PlaybackItem(
      id: 'song',
      title: 'Song',
      projectId: 'project',
      audioAsset: _audio,
    ),
  ],
  currentIndex: 0,
);

Future<_Projects> _showPlayer(
  WidgetTester tester,
  ProjectManifest project, {
  bool withImporter = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 900);
  final session = _Session(_state());
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    session.close();
  });
  final repository = _Projects(project);
  final audio = _Audio();
  await tester.pumpWidget(
    MaterialApp(
      home: PlayerScreen(
        projectId: project.id,
        dependencies: PlayerScreenDependencies(
          projectRepository: repository,
          audioPlayer: audio,
          playbackSession: session,
          lyricFileImport: withImporter ? LocalLyricFileImportService() : null,
          immersiveKtv: ImmersiveKtvDependencies(
            projectRepository: repository,
            metadataRepository: _Metadata(),
            audioPlayer: audio,
            playbackSession: session,
            pathCanonicalizer: _Canonicalizer(),
            microphoneService: _Microphone(),
            recordingService: _Recording(),
            takeHistoryStore: _History(),
            previewService: _Preview(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('untimed lyrics are static reference text without KTV', (
    tester,
  ) async {
    await _showPlayer(
      tester,
      _project(
        document: const LyricDocument(
          language: 'zh',
          lines: _plainLines,
          metadata: {'source': 'pasted-text'},
        ),
      ),
    );

    expect(find.text(referenceLyricsTitle), findsOneWidget);
    expect(find.text('第一句参考'), findsOneWidget);
    expect(find.text('第二句参考'), findsOneWidget);
    expect(find.textContaining('来源：粘贴'), findsOneWidget);
    expect(find.text('同步歌词'), findsNothing);
    expect(find.byTooltip('进入 KTV'), findsNothing);
    // Nothing offers to seek: every line's time is 0:00.
    final seekable = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.hint == PlayerLyricSemantics.seekHint,
    );
    expect(seekable, findsNothing);
    // KTV mode cannot be chosen.
    final ktvChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'KTV'),
    );
    expect(ktvChip.onSelected, isNull);
    // The way to timing is offered.
    expect(find.byKey(const ValueKey('reference-lyrics-open-editor')),
        findsOneWidget);
    // Without lyric sites there is no online search button.
    expect(find.byKey(const ValueKey('reference-lyrics-find-timed')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timed lyrics keep the synced list and KTV', (tester) async {
    await _showPlayer(
      tester,
      _project(
        document: const LyricDocument(
          language: 'zh',
          lines: [
            LyricLine(
              text: '有时间的歌词',
              startTime: Duration(seconds: 1),
              endTime: Duration(seconds: 3),
            ),
          ],
        ),
      ),
    );
    expect(find.text('同步歌词'), findsOneWidget);
    expect(find.text(referenceLyricsTitle), findsNothing);
    expect(find.byTooltip('进入 KTV'), findsOneWidget);
  });

  testWidgets('no lyrics offers paste and file import', (tester) async {
    await _showPlayer(tester, _project());
    expect(find.text('这个工程还没有歌词'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-paste-lyrics')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player-import-lyrics-file')),
      findsOneWidget,
    );
    // No lyric sites were provided.
    expect(find.byKey(const ValueKey('player-fetch-lyrics')), findsNothing);
  });

  testWidgets('no importer keeps the old empty state', (tester) async {
    await _showPlayer(tester, _project(), withImporter: false);
    expect(find.text('这个工程还没有歌词'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-paste-lyrics')), findsNothing);
  });

  testWidgets('pasted plain text is saved and shown as reference lyrics', (
    tester,
  ) async {
    final repository = await _showPlayer(tester, _project());
    await tester.tap(find.byKey(const ValueKey('player-paste-lyrics')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paste-lyrics-text')),
      '粘贴的第一句\n粘贴的第二句',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('paste-lyrics-save')));
    await tester.pumpAndSettle();

    final saved = repository.saved.single;
    expect(saved.hasUntimedLyrics, isTrue);
    expect(saved.metadata['lyricSource'], 'pasted-text');
    expect(find.text(referenceLyricsTitle), findsOneWidget);
    expect(find.text('粘贴的第一句'), findsOneWidget);
    expect(find.textContaining('已保存参考歌词'), findsOneWidget);
  });

  testWidgets('the fullscreen stage explains untimed lyrics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullscreenKtvLyricStage(
            document: LyricDocument(language: 'zh', lines: _plainLines),
            position: Duration(seconds: 5),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('fullscreen-ktv-untimed-lyrics')),
      findsOneWidget,
    );
    expect(find.text(FullscreenKtvLyricStage.untimedMessage), findsOneWidget);
    expect(find.text('第一句参考'), findsNothing);
    expect(
      fullscreenKtvCurrentLyricIndex(
        const LyricDocument(language: 'zh', lines: _plainLines),
        const Duration(seconds: 5),
      ),
      isNull,
    );
  });

  test('lyricSourceLabel names where lyrics came from', () {
    expect(lyricSourceLabel(const {'onlineSourceLabel': '网易云音乐'}), '网易云音乐');
    expect(lyricSourceLabel(const {'source': 'pasted-text'}), '粘贴');
    expect(lyricSourceLabel(const {'source': 'imported-file'}), '歌词文件');
    expect(lyricSourceLabel(const {}), isNull);
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.project);
  ProjectManifest project;
  final saved = <ProjectManifest>[];

  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;

  @override
  Future<ProjectManifest> updateProject(ProjectManifest next) async {
    saved.add(next);
    project = next;
    return next;
  }
}

class _Session extends Fake implements PlaybackSessionService {
  _Session(this._state);
  final PlaybackSessionState _state;
  final _controller = StreamController<PlaybackSessionState>.broadcast();
  @override
  PlaybackSessionState get currentState => _state;
  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;
  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}

  void close() => _controller.close();
}

class _Audio extends Fake implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();
  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
}

class _Metadata extends Fake implements LocalMediaMetadataRepository {}

class _Canonicalizer extends Fake implements AudioPathCanonicalizer {}

class _Microphone extends Fake implements KtvMicrophoneService {}

class _Recording extends Fake implements KtvRecordingService {}

class _History extends Fake implements KtvTakeHistoryStore {}

class _Preview extends Fake implements AudioPreviewService {}
