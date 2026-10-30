import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/home/presentation/screens/dashboard_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/play_history_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';

void main() {
  late _TestProjectRepository projects;
  late _TestPlayHistoryRepository history;
  late _TestPlaybackSessionService playbackSession;
  late _TestAudioPlayerService audioPlayer;
  late _TestTranscriptionQueue transcriptionQueue;

  setUp(() {
    projects = _TestProjectRepository();
    history = _TestPlayHistoryRepository();
    playbackSession = _TestPlaybackSessionService();
    audioPlayer = _TestAudioPlayerService();
    transcriptionQueue = _TestTranscriptionQueue();
  });

  Widget buildScreen() => MaterialApp(
    home: DashboardScreen(
      projectRepository: projects,
      playHistoryRepository: history,
      playbackSessionService: playbackSession,
      audioPlayerService: audioPlayer,
      transcriptionQueue: transcriptionQueue,
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
  });

  testWidgets('retries recent-project loading after an error', (
    WidgetTester tester,
  ) async {
    projects.failFirstRequest = true;

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
}

class _TestProjectRepository implements ProjectRepository {
  int calls = 0;
  bool failFirstRequest = false;

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async {
    calls++;
    if (failFirstRequest && calls == 1) {
      throw StateError('fixture read failure');
    }
    return const <ProjectManifest>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlayHistoryRepository implements PlayHistoryRepository {
  int calls = 0;

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    calls++;
    return const <PlayHistory>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlaybackSessionService implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();

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
