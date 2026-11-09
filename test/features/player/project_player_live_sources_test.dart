import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

const _original = AudioAsset(originalPath: '/song.mp3', format: 'mp3');
const _withBacking = AudioAsset(
  originalPath: '/song.mp3',
  instrumentalPath: '/backing.mp3',
  format: 'mp3',
);

ProjectManifest _project(AudioAsset asset) => ProjectManifest(
  id: 'project',
  name: 'Song',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  audioAsset: asset,
  lyricDocument: const LyricDocument(
    language: 'zh',
    lines: [
      LyricLine(
        text: '歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
      ),
    ],
  ),
);

PlaybackSessionState _state(
  AudioAsset asset, {
  String? projectId = 'project',
}) => PlaybackSessionState(
  queue: [
    PlaybackItem(
      id: 'song',
      title: 'Song',
      projectId: projectId,
      audioAsset: asset,
    ),
  ],
  currentIndex: 0,
);

Future<void> _showPlayer(
  WidgetTester tester,
  ProjectManifest project,
  _Session session,
  _Audio audio,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 768);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    session.close();
  });
  final repository = _Projects(project);
  await tester.pumpWidget(
    MaterialApp(
      home: PlayerScreen(
        projectId: project.id,
        dependencies: PlayerScreenDependencies(
          projectRepository: repository,
          audioPlayer: audio,
          playbackSession: session,
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
}

Future<void> _expectKtvBacking(WidgetTester tester, bool enabled) async {
  await tester.tap(find.byTooltip('进入 KTV'));
  await tester.pumpAndSettle();
  final tile = tester.widget<ListTile>(
    find.ancestor(of: find.text('纯伴奏'), matching: find.byType(ListTile)),
  );
  expect(tile.enabled, enabled);
  Navigator.of(tester.element(find.text('纯伴奏'))).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('open project player follows guarded session source changes', (
    tester,
  ) async {
    final session = _Session(_state(_original));
    final audio = _Audio();
    await _showPlayer(tester, _project(_original), session, audio);
    expect(find.widgetWithText(ChoiceChip, '伴奏'), findsNothing);
    await _expectKtvBacking(tester, false);

    session.emit(_state(_withBacking));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '伴奏'), findsOneWidget);
    await _expectKtvBacking(tester, true);
    await tester.tap(find.widgetWithText(ChoiceChip, '伴奏'));
    await tester.pump();
    expect(audio.switches, [AudioSourceType.instrumental]);
    expect(session.playCalls, 0);

    session.emit(_state(_original));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '伴奏'), findsNothing);
    await _expectKtvBacking(tester, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'active session wins over newer project snapshot after rejected sync',
    (tester) async {
      final session = _Session(_state(_original));
      await _showPlayer(tester, _project(_withBacking), session, _Audio());
      expect(find.widgetWithText(ChoiceChip, '伴奏'), findsNothing);
      await _expectKtvBacking(tester, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open KTV sheet tracks changes and rejects another item', (
    tester,
  ) async {
    final session = _Session(_state(_original));
    final audio = _Audio();
    await _showPlayer(tester, _project(_original), session, audio);
    await tester.tap(find.byTooltip('进入 KTV'));
    await tester.pumpAndSettle();

    ListTile tile(String label) => tester.widget<ListTile>(
      find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
    );
    expect(tile('纯伴奏').enabled, isFalse);
    session.emit(_state(_withBacking));
    await tester.pumpAndSettle();
    expect(tile('纯伴奏').enabled, isTrue);
    session.emit(_state(_original));
    await tester.pumpAndSettle();
    expect(tile('纯伴奏').enabled, isFalse);
    session.emit(_state(_withBacking, projectId: null));
    await tester.pumpAndSettle();
    expect(tile('原唱伴唱').enabled, isFalse);
    expect(tile('纯伴奏').enabled, isFalse);
    expect(find.textContaining('当前播放项已变化'), findsOneWidget);
    expect(audio.switches, isEmpty);
    Navigator.of(tester.element(find.text('纯伴奏'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection is rechecked before changing the source', (
    tester,
  ) async {
    final session = _Session(_state(_withBacking));
    final audio = _Audio();
    await _showPlayer(tester, _project(_original), session, audio);
    await tester.tap(find.byTooltip('进入 KTV'));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('纯伴奏'), matching: find.byType(ListTile)),
    );
    tile.onTap!();
    session.emit(_state(_original));
    await tester.pumpAndSettle();
    expect(audio.switches, isEmpty);
    expect(find.textContaining('播放项或音轨已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection retains the path visible at tap when the track changes', (
    tester,
  ) async {
    final session = _Session(_state(_withBacking));
    final audio = _Audio();
    await _showPlayer(tester, _project(_original), session, audio);
    await tester.tap(find.byTooltip('进入 KTV'));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('纯伴奏'), matching: find.byType(ListTile)),
    );
    tile.onTap!();
    session.emit(_state(_withBacking.copyWith(instrumentalPath: '/new.mp3')));
    await tester.pumpAndSettle();
    expect(audio.switches, isEmpty);
    expect(find.textContaining('播放项或音轨已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch completion cannot open KTV for a changed item', (
    tester,
  ) async {
    final session = _Session(_state(_withBacking));
    final pending = Completer<void>();
    final audio = _Audio(pendingSwitch: pending);
    await _showPlayer(tester, _project(_original), session, audio);
    await tester.tap(find.byTooltip('进入 KTV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯伴奏'));
    await tester.pump();
    expect(audio.switches, [AudioSourceType.instrumental]);
    session.emit(_state(_original, projectId: null));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('播放项或音轨已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch completion rejects a replacement of the selected path', (
    tester,
  ) async {
    final session = _Session(_state(_withBacking));
    final pending = Completer<void>();
    final audio = _Audio(pendingSwitch: pending);
    await _showPlayer(tester, _project(_original), session, audio);
    await tester.tap(find.byTooltip('进入 KTV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯伴奏'));
    await tester.pump();
    expect(audio.switches, [AudioSourceType.instrumental]);
    session.emit(_state(_withBacking.copyWith(instrumentalPath: '/new.mp3')));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('播放项或音轨已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated queue item never supplies project source options', (
    tester,
  ) async {
    final session = _Session(_state(_withBacking, projectId: null));
    await _showPlayer(tester, _project(_original), session, _Audio());
    expect(find.widgetWithText(ChoiceChip, '伴奏'), findsNothing);
    await _expectKtvBacking(tester, false);
    expect(tester.takeException(), isNull);
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.project);
  final ProjectManifest project;
  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;
}

class _Session extends Fake implements PlaybackSessionService {
  _Session(this._state);
  PlaybackSessionState _state;
  final _controller = StreamController<PlaybackSessionState>.broadcast();
  int playCalls = 0;
  @override
  PlaybackSessionState get currentState => _state;
  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;
  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    playCalls++;
  }

  void emit(PlaybackSessionState state) {
    _state = state;
    _controller.add(state);
  }

  void close() => _controller.close();
}

class _Audio extends Fake implements AudioPlayerService {
  _Audio({this.pendingSwitch});
  final Completer<void>? pendingSwitch;
  final switches = <AudioSourceType>[];
  @override
  PlaybackState get currentState => const PlaybackState.idle();
  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();
  @override
  Future<void> switchSource(AudioSourceType source) async {
    switches.add(source);
    await pendingSwitch?.future;
  }
}

class _Metadata extends Fake implements LocalMediaMetadataRepository {}

class _Canonicalizer extends Fake implements AudioPathCanonicalizer {}

class _Microphone extends Fake implements KtvMicrophoneService {}

class _Recording extends Fake implements KtvRecordingService {}

class _History extends Fake implements KtvTakeHistoryStore {}

class _Preview extends Fake implements AudioPreviewService {}
