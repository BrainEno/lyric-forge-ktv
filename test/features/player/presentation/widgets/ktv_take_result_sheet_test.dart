import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/audio_preview_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_take_result_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  const stemPath = '/recordings/take-1/voice.wav';
  const mixPath = '/recordings/take-1/mix.wav';

  late _FakePreviewService preview;
  late List<String> log;

  setUp(() {
    log = <String>[];
    preview = _FakePreviewService(log);
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    KtvRecordingSession? session,
    KtvRecordingService? recordingService,
    PreviewFileProbe? probe,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KtvTakeResultSheet(
            initialSession: session ?? _session(),
            recordingService: recordingService ?? _FakeRecordingService(),
            previewService: preview,
            previewFileExists: probe ?? (path) async => true,
          ),
        ),
      ),
    );
    // One frame for the post-frame load, one turn for the file probe.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('试听通过试听服务加载原始人声，不自己建播放器', (tester) async {
    await pumpSheet(tester);

    expect(preview.loaded, <String>[stemPath]);
    expect(find.text('人声 stem（00:12）'), findsOneWidget);
    expect(find.text('播放原始人声'), findsOneWidget);
  });

  testWidgets('有混音成品时默认试听混音，切回原始人声会重新加载', (tester) async {
    await pumpSheet(tester, session: _session(mixedOutputPath: mixPath));

    expect(preview.loaded, <String>[mixPath]);
    expect(find.text('播放混音成品'), findsOneWidget);

    await tester.tap(find.text('原始人声'));
    await tester.pump();
    await tester.pump();

    expect(preview.loaded, <String>[mixPath, stemPath]);
    expect(find.text('播放原始人声'), findsOneWidget);
  });

  testWidgets('播放与暂停按钮驱动试听服务，并跟随服务状态', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('播放原始人声'));
    await tester.pump();
    expect(log, contains('play'));

    preview.emit(const AudioPreviewState.idle().copyWith(isPlaying: true));
    await tester.pump();
    expect(find.text('暂停原始人声'), findsOneWidget);

    await tester.tap(find.text('暂停原始人声'));
    await tester.pump();
    expect(log, contains('pause'));
  });

  testWidgets('文件不存在时说明原因且不调用试听服务', (tester) async {
    await pumpSheet(tester, probe: (path) async => false);

    expect(preview.loaded, isEmpty);
    expect(find.text('原始人声文件不存在或不可用'), findsOneWidget);
  });

  testWidgets('导出混音后自动切到混音成品', (tester) async {
    final recordingService = _FakeRecordingService(
      exported: _session(mixedOutputPath: mixPath),
    );
    await pumpSheet(tester, recordingService: recordingService);

    await tester.tap(find.text('导出 WAV 混音'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(recordingService.exportCount, 1);
    expect(preview.loaded, <String>[stemPath, mixPath]);
    expect(find.text('重新导出混音'), findsOneWidget);
  });

  testWidgets('关闭试听面板时停止试听', (tester) async {
    await pumpSheet(tester);

    await tester.pumpWidget(const SizedBox());

    expect(log, contains('stop'));
  });
}

KtvRecordingSession _session({
  String? mixedOutputPath,
  Duration duration = const Duration(seconds: 12),
}) {
  return KtvRecordingSession(
    id: 'take-1',
    projectId: 'project-1',
    startedAt: DateTime(2026, 11, 3),
    backingSource: AudioSourceType.instrumental,
    backingPath: '/projects/project-1/instrumental.wav',
    startPosition: Duration.zero,
    duration: duration,
    micStemPath: '/recordings/take-1/voice.wav',
    manifestPath: '/recordings/take-1/take.json',
    mixedOutputPath: mixedOutputPath,
    backingVolume: 0.6,
    monitorMicGain: 1.0,
  );
}

class _FakePreviewService implements AudioPreviewService {
  _FakePreviewService(this.log);

  final List<String> log;
  final List<String> loaded = <String>[];
  final StreamController<AudioPreviewState> _controller =
      StreamController<AudioPreviewState>.broadcast();
  AudioPreviewState _state = const AudioPreviewState.idle();

  void emit(AudioPreviewState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  AudioPreviewState get currentState => _state;

  @override
  Stream<AudioPreviewState> get stateStream => _controller.stream;

  @override
  Future<Duration?> loadFile(String path) async {
    loaded.add(path);
    log.add('load:$path');
    _state = _state.copyWith(isLoaded: true, isPlaying: false);
    return const Duration(seconds: 12);
  }

  @override
  Future<void> play() async => log.add('play');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> seek(Duration position) async => log.add('seek');

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

class _FakeRecordingService implements KtvRecordingService {
  _FakeRecordingService({KtvRecordingSession? exported}) : _exported = exported;

  final KtvRecordingSession? _exported;
  int exportCount = 0;

  @override
  Stream<KtvRecordingState> get stateStream =>
      const Stream<KtvRecordingState>.empty();

  @override
  KtvRecordingState get currentState => const KtvRecordingState();

  @override
  Future<void> startRecording(ProjectManifest project) async {}

  @override
  Future<KtvRecordingSession?> stopRecording() async => null;

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async {
    exportCount += 1;
    return _exported ?? session;
  }

  @override
  Future<void> dispose() async {}
}
