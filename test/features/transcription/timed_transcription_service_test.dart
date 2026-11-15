import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/operation_timings.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/timed_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_degradation.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

class _FakeTranscriptionService implements TranscriptionService {
  Future<TranscriptionResult> Function(TranscriptionRequest request)? onRun;
  final StreamController<TranscriptionProgress> progress =
      StreamController<TranscriptionProgress>.broadcast();
  int cancelCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => progress.stream;

  @override
  bool get isRunning => true;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) =>
      onRun!(request);

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// A canonical 16 kHz mono 16-bit WAV header for [seconds] of audio.
Uint8List _wavHeader(int seconds, {int? dataSize, bool listChunk = false}) {
  const sampleRate = 16000;
  const byteRate = sampleRate * 2;
  final data = dataSize ?? byteRate * seconds;
  final list = listChunk ? 8 + 5 + 1 : 0; // odd-sized chunk plus padding
  final bytes = ByteData(44 + list);
  void tag(int offset, String value) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + list + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  var offset = 36;
  if (listChunk) {
    tag(offset, 'LIST');
    bytes.setUint32(offset + 4, 5, Endian.little);
    offset += 8 + 5 + 1;
  }
  tag(offset, 'data');
  bytes.setUint32(offset + 4, data, Endian.little);
  return bytes.buffer.asUint8List();
}

const _config = TranscriptionConfig(
  whisperExecutable: 'whisper-cli',
  modelPath: 'ggml-large-v3.bin',
  mode: TranscriptionMode.highestQuality,
  language: 'zh',
);

const _request = TranscriptionRequest(
  inputAudioPath: '/Users/alice/Music/song.flac',
  outputDirectory: '/tmp/out',
  config: _config,
);

TranscriptionResult _result({Map<String, dynamic> metadata = const {}}) =>
    TranscriptionResult(
      lyrics: LyricDocument(
        language: 'zh',
        lines: const [
          LyricLine(
            text: '秘密的歌词',
            startTime: Duration.zero,
            endTime: Duration(seconds: 2),
          ),
          LyricLine(
            text: '第二行',
            startTime: Duration(seconds: 2),
            endTime: Duration(seconds: 4),
          ),
        ],
        metadata: metadata,
      ),
      normalizedAudioPath: '/tmp/out/normalized.wav',
      rawJsonPath: '/tmp/out/raw.json',
      detectedLanguage: 'zh',
    );

void main() {
  late _FakeTranscriptionService delegate;
  late OperationTimings timings;
  late AppLogger logger;

  setUp(() {
    delegate = _FakeTranscriptionService();
    logger = AppLogger(sinks: [MemoryLogSink()]);
    timings = OperationTimings(logger: logger);
  });

  TimedTranscriptionService service({
    Future<Duration?> Function(String path)? mediaDurationOf,
  }) => TimedTranscriptionService(
    delegate: delegate,
    timings: timings,
    logger: logger,
    mediaDurationOf: mediaDurationOf ?? (_) async => const Duration(minutes: 4),
    memoryProbe: () => const {'rssMb': 300, 'peakRssMb': 2100},
  );

  test('records a successful run with media duration and metadata', () async {
    delegate.onRun = (_) async => _result(
      metadata: Map<String, dynamic>.from(
        TranscriptionQualityMetadata.degradedFields(
          TranscriptionDegradationReason.qwenUnavailable,
        ),
      ),
    );
    final result = await service().transcribe(_request);

    expect(result.lyrics.lines, hasLength(2));
    final sample = timings
        .samplesFor(TimedTranscriptionService.operation)
        .single;
    expect(sample.outcome, OperationOutcome.success);
    expect(sample.mediaDuration, const Duration(minutes: 4));
    expect(sample.attributes, containsPair('mode', 'highestQuality'));
    expect(sample.attributes, containsPair('language', 'zh'));
    expect(sample.attributes, containsPair('lines', 2));
    expect(sample.attributes, containsPair('degraded', true));
    expect(
      sample.attributes,
      containsPair('degradationReason', 'qwenUnavailable'),
    );
    expect(sample.attributes, containsPair('peakRssMb', 2100));
  });

  test('never logs lyric text or the input path', () async {
    delegate.onRun = (_) async => _result();
    await service().transcribe(_request);
    final logged = logger.memory!.records
        .map((record) => record.format(includeStackTrace: true))
        .join('\n');
    expect(logged, isNot(contains('秘密的歌词')));
    expect(logged, isNot(contains('song.flac')));
    expect(logged, contains('Recognition finished: 2 lines'));
  });

  test('cancellation is recorded as cancelled and rethrown', () async {
    delegate.onRun = (_) async => throw const TranscriptionException(
      '已取消',
      kind: TranscriptionFailureKind.cancelled,
    );
    await expectLater(
      service().transcribe(_request),
      throwsA(isA<TranscriptionException>()),
    );
    final sample = timings
        .samplesFor(TimedTranscriptionService.operation)
        .single;
    expect(sample.outcome, OperationOutcome.cancelled);
    expect(sample.attributes, containsPair('failureKind', 'cancelled'));
    expect(
      logger.memory!.records.where(
        (record) => record.level == LogLevel.warning,
      ),
      isEmpty,
    );
  });

  test('a failure records its kind and logs a warning with details', () async {
    delegate.onRun = (_) async => throw const TranscriptionException(
      '模型文件损坏',
      details: 'exit 3: cannot open /Users/alice/models/ggml.bin',
      kind: TranscriptionFailureKind.environment,
    );
    await expectLater(
      service().transcribe(_request),
      throwsA(isA<TranscriptionException>()),
    );
    final sample = timings
        .samplesFor(TimedTranscriptionService.operation)
        .single;
    expect(sample.outcome, OperationOutcome.failure);
    expect(sample.attributes, containsPair('failureKind', 'environment'));
    final warning = logger.memory!.records.singleWhere(
      (record) => record.level == LogLevel.warning,
    );
    expect(warning.message, contains('environment'));
    expect(warning.message, contains('exit 3: cannot open ~/models/ggml.bin'));
  });

  test('an unexpected error is recorded and logged as an error', () async {
    delegate.onRun = (_) async => throw StateError('boom');
    await expectLater(service().transcribe(_request), throwsStateError);
    expect(
      timings.samplesFor(TimedTranscriptionService.operation).single.attributes,
      containsPair('failureKind', 'unexpected'),
    );
    expect(
      logger.memory!.records.last.level,
      LogLevel.error,
    );
  });

  test('a failing duration probe does not fail recognition', () async {
    delegate.onRun = (_) async => _result();
    final result = await service(
      mediaDurationOf: (_) async => throw const FileSystemException('gone'),
    ).transcribe(_request);
    expect(result.detectedLanguage, 'zh');
    expect(
      timings
          .samplesFor(TimedTranscriptionService.operation)
          .single
          .mediaDuration,
      isNull,
    );
  });

  test('delegates progress, cancel and dispose', () async {
    final subject = service();
    final events = <TranscriptionProgress>[];
    final subscription = subject.progressStream.listen(events.add);
    delegate.progress.add(
      TranscriptionProgress(
        stage: TranscriptionStage.values.first,
        progress: 0.5,
        message: 'x',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await subject.cancel();
    await subject.dispose();
    await subscription.cancel();
    expect(events, hasLength(1));
    expect(subject.isRunning, isTrue);
    expect(delegate.cancelCalls, 1);
    expect(delegate.disposeCalls, 1);
  });

  group('WAV duration', () {
    test('parses a canonical header', () {
      expect(
        pcmWavDurationFromHeader(_wavHeader(180)),
        const Duration(minutes: 3),
      );
    });

    test('skips odd-sized chunks before data', () {
      expect(
        pcmWavDurationFromHeader(_wavHeader(5, listChunk: true)),
        const Duration(seconds: 5),
      );
    });

    test('uses the file length for streaming headers', () {
      final header = _wavHeader(0, dataSize: 0xFFFFFFFF);
      expect(
        pcmWavDurationFromHeader(header, fileLength: 44 + 32000 * 7),
        const Duration(seconds: 7),
      );
    });

    test('rejects non-WAV input', () {
      expect(pcmWavDurationFromHeader(Uint8List(4)), isNull);
      expect(
        pcmWavDurationFromHeader(Uint8List.fromList('RIFF0000AVI '.codeUnits)),
        isNull,
      );
    });

    test('reads a real file header without the samples', () async {
      final dir = await Directory.systemTemp.createTemp('timed_wav');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.wav');
      await file.writeAsBytes([..._wavHeader(2), ...Uint8List(32000 * 2)]);
      expect(await readPcmWavDuration(file.path), const Duration(seconds: 2));
      expect(await readPcmWavDuration('${dir.path}/missing.wav'), isNull);
      expect(await readPcmWavDuration(''), isNull);
    });
  });
}
