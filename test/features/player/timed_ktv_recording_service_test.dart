import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/operation_timings.dart';
import 'package:lyric_forge_ktv/features/player/data/services/timed_ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_microphone_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

class _FakeRecording implements KtvRecordingService {
  Object? startError;
  Object? stopError;
  Object? exportError;
  KtvRecordingSession? stopResult;
  final List<String> calls = [];
  double? lastVoiceVolume;
  double? lastBackingVolume;

  @override
  Stream<KtvRecordingState> get stateStream => const Stream.empty();

  @override
  KtvRecordingState get currentState =>
      const KtvRecordingState(isRecording: true);

  @override
  Future<void> startRecording(ProjectManifest project) async {
    calls.add('start:${project.id}');
    if (startError != null) throw startError!;
  }

  @override
  Future<KtvRecordingSession?> stopRecording() async {
    calls.add('stop');
    if (stopError != null) throw stopError!;
    return stopResult;
  }

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async {
    calls.add('export');
    lastVoiceVolume = voiceVolume;
    lastBackingVolume = backingVolume;
    if (exportError != null) throw exportError!;
    return session.copyWith(mixedOutputPath: '/tmp/mix.m4a');
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

class _FakeMicrophone implements KtvMicrophoneService {
  _FakeMicrophone(this.currentState);

  @override
  final KtvMicrophoneState currentState;

  @override
  Stream<KtvMicrophoneState> get stateStream => const Stream.empty();

  @override
  Stream<Uint8List> get rawPcm16Stream => const Stream.empty();

  @override
  Future<void> refreshInputDevices() async {}

  @override
  Future<void> selectInputDevice(String? deviceId) async {}

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  Future<void> setMicGain(double gain) async {}

  @override
  Future<void> setMonitorDelay(Duration delay) async {}

  @override
  Future<void> dispose() async {}
}

final _project = ProjectManifest(
  id: 'p1',
  name: 'Song',
  createdAt: DateTime.utc(2026, 11, 15),
  updatedAt: DateTime.utc(2026, 11, 15),
);

KtvRecordingSession _session({bool reliable = true}) => KtvRecordingSession(
  id: 's1',
  projectId: 'p1',
  startedAt: DateTime.utc(2026, 11, 15),
  backingSource: AudioSourceType.values.first,
  backingPath: '/tmp/backing.wav',
  startPosition: Duration.zero,
  duration: const Duration(minutes: 5),
  micStemPath: '/tmp/mic.wav',
  manifestPath: '/tmp/take.json',
  backingVolume: 0.8,
  monitorMicGain: 1,
  alignmentReliable: reliable,
  alignmentIssue: reliable ? null : 'backing restarted',
);

void main() {
  late _FakeRecording delegate;
  late OperationTimings timings;
  late AppLogger logger;

  setUp(() {
    delegate = _FakeRecording();
    logger = AppLogger(sinks: [MemoryLogSink()]);
    timings = OperationTimings(logger: logger);
  });

  TimedKtvRecordingService service({KtvMicrophoneService? microphone}) =>
      TimedKtvRecordingService(
        delegate: delegate,
        timings: timings,
        microphone: microphone,
        logger: logger,
        memoryProbe: () => const {'peakRssMb': 640},
      );

  test('start records the microphone latency the device reported', () async {
    final subject = service(
      microphone: _FakeMicrophone(
        const KtvMicrophoneState(
          isMonitoring: true,
          monitorDelay: Duration(milliseconds: 40),
          engineLatency: Duration(milliseconds: 12),
        ),
      ),
    );
    await subject.startRecording(_project);

    expect(delegate.calls, ['start:p1']);
    final sample = timings
        .samplesFor(TimedKtvRecordingService.startOperation)
        .single;
    expect(sample.outcome, OperationOutcome.success);
    expect(sample.attributes, {
      'monitoring': true,
      'monitorDelayMs': 40,
      'engineLatencyMs': 12,
    });
  });

  test('start without a microphone service records no attributes', () async {
    await service().startRecording(_project);
    expect(
      timings
          .samplesFor(TimedKtvRecordingService.startOperation)
          .single
          .attributes,
      isEmpty,
    );
  });

  test('a failed start is recorded, logged and rethrown', () async {
    delegate.startError = StateError('no backing track');
    await expectLater(service().startRecording(_project), throwsStateError);
    final sample = timings
        .samplesFor(TimedKtvRecordingService.startOperation)
        .single;
    expect(sample.outcome, OperationOutcome.failure);
    expect(sample.attributes, {'error': 'StateError'});
    expect(logger.memory!.records.last.level, LogLevel.warning);
  });

  test(
    'stop records the take length and warns on unreliable alignment',
    () async {
      delegate.stopResult = _session(reliable: false);
      final session = await service().stopRecording();

      expect(session!.id, 's1');
      final sample = timings
          .samplesFor(TimedKtvRecordingService.stopOperation)
          .single;
      expect(sample.mediaDuration, const Duration(minutes: 5));
      expect(sample.attributes, containsPair('alignmentReliable', false));
      expect(
        logger.memory!.records.map((record) => record.message),
        contains('Take alignment is not reliable: backing restarted'),
      );
    },
  );

  test('stop without a session counts as cancelled', () async {
    expect(await service().stopRecording(), isNull);
    expect(
      timings.samplesFor(TimedKtvRecordingService.stopOperation).single.outcome,
      OperationOutcome.cancelled,
    );
  });

  test('a failed stop is recorded and rethrown', () async {
    delegate.stopError = StateError('recorder lost');
    await expectLater(service().stopRecording(), throwsStateError);
    expect(
      timings.samplesFor(TimedKtvRecordingService.stopOperation).single.outcome,
      OperationOutcome.failure,
    );
  });

  test('export passes volumes through and yields a real-time factor', () async {
    final exported = await service().exportMix(
      _session(),
      voiceVolume: 0.7,
      backingVolume: 0.5,
    );
    expect(exported.mixedOutputPath, '/tmp/mix.m4a');
    expect(delegate.lastVoiceVolume, 0.7);
    expect(delegate.lastBackingVolume, 0.5);
    final sample = timings
        .samplesFor(TimedKtvRecordingService.exportOperation)
        .single;
    expect(sample.mediaDuration, const Duration(minutes: 5));
    expect(sample.realTimeFactor, isNotNull);
    expect(sample.attributes, containsPair('peakRssMb', 640));
  });

  test('a failed export is recorded and rethrown', () async {
    delegate.exportError = const FormatException('ffmpeg exit 1');
    await expectLater(service().exportMix(_session()), throwsFormatException);
    final sample = timings
        .samplesFor(TimedKtvRecordingService.exportOperation)
        .single;
    expect(sample.outcome, OperationOutcome.failure);
    expect(sample.attributes, containsPair('error', 'FormatException'));
  });

  test('state and dispose are delegated', () async {
    final subject = service();
    expect(subject.currentState.isRecording, isTrue);
    expect(await subject.stateStream.isEmpty, isTrue);
    await subject.dispose();
    expect(delegate.calls, ['dispose']);
  });
}
