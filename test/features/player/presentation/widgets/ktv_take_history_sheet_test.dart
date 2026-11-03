import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/audio_preview_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_take_history_store.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_take_history_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  late _FakeTakeHistoryStore store;
  late _FakeRecordingService recording;

  final project = ProjectManifest(
    id: 'song',
    name: 'Song',
    createdAt: DateTime.utc(2026, 10, 10),
    updatedAt: DateTime.utc(2026, 10, 10),
    audioAsset: const AudioAsset(
      originalPath: '/music/backing.wav',
      format: 'wav',
    ),
  );

  setUp(() {
    store = _FakeTakeHistoryStore(takes: [_take()]);
    recording = _FakeRecordingService();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KtvTakeHistorySheet(
            project: project,
            takeHistoryStore: store,
            recordingService: recording,
            previewService: _FakePreviewService(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('录音或导出期间拒绝收藏、重命名和删除，并说明原因', (tester) async {
    recording.emit(const KtvRecordingState(isExporting: true));
    await pumpSheet(tester);

    // The lock is stated up front, not discovered by tapping.
    expect(find.text(KtvTakeHistorySheet.lockedExportMessage), findsOneWidget);

    // The favourite action is disabled while the take directory is being
    // rewritten by ffmpeg.
    final favourite = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.star_border_rounded),
    );
    expect(favourite.onPressed, isNull);

    // Opening a take is refused too: the result sheet would start a second
    // player on top of a running export.
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();

    expect(store.mutations, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(KtvTakeHistorySheet.lockedExportMessage),
      findsNWidgets(2),
      reason: '表内提示与拒绝时的 SnackBar 使用同一句话',
    );
  });

  testWidgets('录音期间给出的是停止录音的提示，而不是导出提示', (tester) async {
    recording.emit(const KtvRecordingState(isRecording: true));
    await pumpSheet(tester);

    await tester.tap(find.byType(ListTile).first);
    await tester.pump();

    expect(find.text(KtvTakeHistorySheet.lockedRecordingMessage), findsWidgets);
    expect(store.mutations, isEmpty);
  });

  testWidgets('未锁定时收藏会写回项目并刷新列表', (tester) async {
    await pumpSheet(tester);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.star_border_rounded),
    );
    await tester.pump();
    await tester.pump();

    expect(store.mutations, hasLength(1));
    expect(store.mutations.single.isFavorite, isTrue);
    expect(store.scanCount, 2, reason: '写入后重新读取演唱历史');
    expect(find.widgetWithIcon(IconButton, Icons.star_rounded), findsOneWidget);
  });

  testWidgets('中断录音的恢复结果在表内提示，不再依赖打开前的 SnackBar', (tester) async {
    store = _FakeTakeHistoryStore(takes: const [], recoveredCount: 2);
    await pumpSheet(tester);

    expect(find.textContaining('已恢复 2 次中断录音'), findsOneWidget);
    expect(find.text('暂无已完成的演唱录音'), findsOneWidget);
  });
}

KtvRecordingSession _take({
  String id = 'take-1',
  bool isFavorite = false,
  String? displayName,
}) {
  return KtvRecordingSession(
    id: id,
    projectId: 'song',
    startedAt: DateTime.utc(2026, 11, 1, 20, 30),
    completedAt: DateTime.utc(2026, 11, 1, 20, 31),
    backingSource: AudioSourceType.instrumental,
    backingPath: '/music/backing.wav',
    startPosition: Duration.zero,
    duration: const Duration(seconds: 30),
    micStemPath: '/recordings/take-1/voice.wav',
    manifestPath: '/recordings/take-1/session.json',
    backingVolume: 0.8,
    monitorMicGain: 1,
    displayName: displayName,
    isFavorite: isFavorite,
  );
}

class _FakeTakeHistoryStore implements KtvTakeHistoryStore {
  _FakeTakeHistoryStore({
    required List<KtvRecordingSession> takes,
    this.recoveredCount = 0,
  }) : _takes = List<KtvRecordingSession>.of(takes);

  final List<KtvRecordingSession> _takes;
  final int recoveredCount;
  final List<KtvRecordingSession> mutations = <KtvRecordingSession>[];
  int scanCount = 0;

  @override
  Future<KtvTakeHistoryScanResult> scanProject(ProjectManifest project) async {
    scanCount += 1;
    return KtvTakeHistoryScanResult(
      takes: _takes,
      recoveredCount: recoveredCount,
    );
  }

  @override
  Future<List<KtvRecordingSession>> listProject(
    ProjectManifest project,
  ) async => _takes;

  @override
  Future<KtvRecordingSession> updateProjectTakeMetadata(
    ProjectManifest project,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  }) async {
    final updated = take.copyWith(
      displayName: displayName,
      clearDisplayName: clearDisplayName,
      isFavorite: isFavorite,
    );
    mutations.add(updated);
    final index = _takes.indexWhere((item) => item.id == take.id);
    if (index >= 0) _takes[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteProjectTake(
    ProjectManifest project,
    KtvRecordingSession take,
  ) async {
    mutations.add(take);
    _takes.removeWhere((item) => item.id == take.id);
  }
}

class _FakeRecordingService implements KtvRecordingService {
  final StreamController<KtvRecordingState> _states =
      StreamController<KtvRecordingState>.broadcast();
  KtvRecordingState _state = const KtvRecordingState();

  void emit(KtvRecordingState state) {
    _state = state;
    _states.add(state);
  }

  @override
  KtvRecordingState get currentState => _state;

  @override
  Stream<KtvRecordingState> get stateStream => _states.stream;

  @override
  Future<void> startRecording(ProjectManifest project) async {}

  @override
  Future<KtvRecordingSession?> stopRecording() async => null;

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async => session;

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

class _FakePreviewService implements AudioPreviewService {
  final StreamController<AudioPreviewState> _states =
      StreamController<AudioPreviewState>.broadcast();

  @override
  AudioPreviewState get currentState => const AudioPreviewState.idle();

  @override
  Stream<AudioPreviewState> get stateStream => _states.stream;

  @override
  Future<Duration?> loadFile(String path) async => const Duration(seconds: 30);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}
