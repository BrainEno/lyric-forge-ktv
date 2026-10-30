import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  group('HighQualityTranscriptionService', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('lyric_forge_asr_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test(
      'shares one prepared WAV with both engines in either engine order',
      () async {
        for (final engineOrder in [
          TranscriptionEngineOrder.qwenPrimary,
          TranscriptionEngineOrder.whisperPrimary,
        ]) {
          final primary = _FakeTranscriptionService(
            result: _result(
              LyricLine(
                text: 'primary lyric',
                startTime: const Duration(seconds: 1),
                endTime: const Duration(seconds: 2),
                confidence: 80,
              ),
            ),
          );
          final fallback = _FakeTranscriptionService(
            result: _result(
              LyricLine(
                text: 'secondary lyric',
                startTime: const Duration(seconds: 3),
                endTime: const Duration(seconds: 4),
                confidence: 90,
              ),
            ),
          );
          var prepareCount = 0;
          final service = HighQualityTranscriptionService(
            primary: primary,
            fallback: fallback,
            sharedAudioPreparer: (request) async {
              prepareCount++;
              expect(request.inputAudioPath, 'unused-by-fake.wav');
              return 'generated-shared.wav';
            },
          );

          try {
            await service.transcribe(
              _request(
                tempDirectory.path,
                engineOrder: engineOrder,
                includeNormalizedInput: false,
              ),
            );

            expect(prepareCount, 1, reason: 'engine order: $engineOrder');
            expect(
              primary.requests.single.normalizedInputAudioPath,
              'generated-shared.wav',
              reason: 'primary engine order: $engineOrder',
            );
            expect(
              fallback.requests.single.normalizedInputAudioPath,
              'generated-shared.wav',
              reason: 'fallback engine order: $engineOrder',
            );
          } finally {
            await service.dispose();
          }
        }
      },
    );

    test(
      'inserts Whisper-only lines as reviewable rows and remaps candidates',
      () async {
        final primaryResult = _resultLines([
          LyricLine(
            text: 'opening verse',
            startTime: const Duration(seconds: 1),
            endTime: const Duration(seconds: 3),
            confidence: 92,
          ),
          LyricLine(
            text: 'hello hello hello hello',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(seconds: 12),
            confidence: 35,
          ),
        ]);
        final fallbackResult = _resultLines([
          LyricLine(
            text: 'opening verse',
            startTime: const Duration(milliseconds: 1100),
            endTime: const Duration(milliseconds: 2900),
            confidence: 92,
          ),
          LyricLine(
            text: 'missing lyric line',
            startTime: const Duration(seconds: 5),
            endTime: const Duration(seconds: 6),
            confidence: 92,
          ),
          LyricLine(
            text: 'yellow submarine',
            startTime: const Duration(milliseconds: 10100),
            endTime: const Duration(milliseconds: 11900),
            confidence: 92,
          ),
        ]);
        final service = HighQualityTranscriptionService(
          primary: _FakeTranscriptionService(result: primaryResult),
          fallback: _FakeTranscriptionService(result: fallbackResult),
        );

        final result = await service.transcribe(_request(tempDirectory.path));
        final lines = result.lyrics.lines;
        final metadata = result.lyrics.metadata;
        final candidates = metadata['fallbackCandidates'] as List;
        final candidate = Map<String, dynamic>.from(candidates.single as Map);

        expect(lines.map((line) => line.text).toList(), [
          'opening verse',
          'missing lyric line',
          'yellow submarine',
        ]);
        expect(lines[1].confidence, 60);
        expect(lines[0].startTime, const Duration(seconds: 1));
        expect(lines[1].startTime, const Duration(seconds: 5));
        expect(lines[2].startTime, const Duration(seconds: 10));
        expect(metadata['secondaryOnlyLineCount'], 1);
        expect(metadata['secondaryOnlyLineIndices'], [1]);
        // The replacement candidate originally referenced primary row 2. Its
        // index must move when a new secondary-only row is inserted before it.
        expect(candidate['lineIndex'], 2);
        expect(lines[2].text, 'yellow submarine');

        await service.dispose();
      },
    );

    test(
      'keeps Whisper primary output and inserts Qwen-only review rows',
      () async {
        final qwenResult = _resultLines([
          LyricLine(
            text: 'opening verse',
            startTime: const Duration(milliseconds: 1100),
            endTime: const Duration(milliseconds: 2900),
            confidence: 92,
          ),
          LyricLine(
            text: 'Qwen heard another line',
            startTime: const Duration(seconds: 5),
            endTime: const Duration(seconds: 6),
            confidence: 92,
          ),
          LyricLine(
            text: 'closing verse',
            startTime: const Duration(milliseconds: 10100),
            endTime: const Duration(milliseconds: 11900),
            confidence: 92,
          ),
        ]);
        final whisperResult = _resultLines([
          LyricLine(
            text: 'opening verse',
            startTime: const Duration(seconds: 1),
            endTime: const Duration(seconds: 3),
            confidence: 92,
          ),
          LyricLine(
            text: 'closing verse',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(seconds: 12),
            confidence: 92,
          ),
        ]);
        final service = HighQualityTranscriptionService(
          primary: _FakeTranscriptionService(result: qwenResult),
          fallback: _FakeTranscriptionService(result: whisperResult),
        );

        final result = await service.transcribe(
          _request(
            tempDirectory.path,
            engineOrder: TranscriptionEngineOrder.whisperPrimary,
          ),
        );

        expect(result.lyrics.lines.map((line) => line.text).toList(), [
          'opening verse',
          'Qwen heard another line',
          'closing verse',
        ]);
        expect(result.lyrics.lines[1].confidence, 60);
        expect(result.lyrics.metadata['primaryEngine'], 'whisper.cpp-large-v3');
        expect(result.lyrics.metadata['secondaryOnlyLineCount'], 1);
        expect(result.lyrics.metadata['secondaryOnlyLineIndices'], [1]);

        await service.dispose();
      },
    );

    test('reports configured model identities in fusion metadata', () async {
      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(
          result: _result(
            LyricLine(
              text: 'hello world',
              startTime: const Duration(seconds: 1),
              endTime: const Duration(seconds: 2),
              confidence: 80,
            ),
          ),
        ),
        fallback: _FakeTranscriptionService(
          result: _result(
            LyricLine(
              text: 'hello world',
              startTime: const Duration(seconds: 1),
              endTime: const Duration(seconds: 2),
              confidence: 90,
            ),
          ),
        ),
      );

      final result = await service.transcribe(
        _request(
          tempDirectory.path,
          qwenModelPath: 'Qwen/Qwen3-ASR-0.6B',
          qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-1.5B',
          whisperModelPath: r'D:\models\ggml-medium.bin',
        ),
      );

      expect(result.lyrics.metadata['primaryEngine'], 'qwen3-asr-0.6b');
      expect(
        result.lyrics.metadata['alignmentEngine'],
        'qwen3-forced-aligner-1.5b',
      );
      expect(result.lyrics.metadata['fallbackEngine'], 'whisper.cpp-medium');

      await service.dispose();
    });

    test('keeps Qwen result when Whisper second opinion fails', () async {
      final primaryResult = _result(
        LyricLine(
          text: '你好世界',
          startTime: const Duration(seconds: 1),
          endTime: const Duration(seconds: 3),
          confidence: 92,
        ),
      );

      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: primaryResult),
        fallback: _FakeTranscriptionService(
          error: const TranscriptionException('Whisper unavailable'),
        ),
      );

      final result = await service.transcribe(_request(tempDirectory.path));

      expect(result.lyrics.lines.single.text, '你好世界');
      expect(result.lyrics.metadata['fallbackStatus'], 'failed');
      expect(
        result.lyrics.metadata['fallbackError'],
        contains('Whisper unavailable'),
      );

      await service.dispose();
    });

    test(
      'replaces only clearly weak Qwen text and preserves Qwen timing',
      () async {
        final primaryResult = _result(
          LyricLine(
            text: 'hello hello hello hello',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(seconds: 13),
            confidence: 35,
          ),
        );

        final fallbackResult = _result(
          LyricLine(
            text: 'yellow submarine',
            startTime: const Duration(milliseconds: 10100),
            endTime: const Duration(milliseconds: 12900),
            confidence: 92,
          ),
        );

        final service = HighQualityTranscriptionService(
          primary: _FakeTranscriptionService(result: primaryResult),
          fallback: _FakeTranscriptionService(result: fallbackResult),
        );

        final result = await service.transcribe(_request(tempDirectory.path));

        final line = result.lyrics.lines.single;
        expect(line.text, 'yellow submarine');
        expect(line.startTime, const Duration(seconds: 10));
        expect(line.endTime, const Duration(seconds: 13));
        expect(result.lyrics.metadata['fallbackStatus'], 'completed');
        expect(result.lyrics.metadata['fallbackAppliedCount'], 1);

        await service.dispose();
      },
    );
    test(
      'surfaces Ashin versus passion as a review candidate without auto-applying',
      () async {
        final primaryResult = _result(
          LyricLine(
            text: 'Ashin lady',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(seconds: 13),
            confidence: 92,
          ),
        );
        final fallbackResult = _result(
          LyricLine(
            text: 'passion lady',
            startTime: const Duration(milliseconds: 10100),
            endTime: const Duration(milliseconds: 12900),
            confidence: 92,
          ),
        );
        final service = HighQualityTranscriptionService(
          primary: _FakeTranscriptionService(result: primaryResult),
          fallback: _FakeTranscriptionService(result: fallbackResult),
        );

        final result = await service.transcribe(_request(tempDirectory.path));
        final metadata = result.lyrics.metadata;
        final candidates = metadata['fallbackCandidates'] as List;
        final candidate = Map<String, dynamic>.from(candidates.single as Map);

        expect(result.lyrics.lines.single.text, 'Ashin lady');
        expect(metadata['fallbackCandidateCount'], 1);
        expect(metadata['fallbackAppliedCount'], 0);
        expect(candidate['alternativeText'], 'passion lady');
        expect(candidate['reason'], 'engine_disagreement_review');
        expect(candidate['similarity'], closeTo(8 / 11, 0.001));

        await service.dispose();
      },
    );

    test('surfaces the same disagreement when Whisper is primary', () async {
      final whisperResult = _result(
        LyricLine(
          text: 'passion lady',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 92,
        ),
      );
      final qwenResult = _result(
        LyricLine(
          text: 'Ashin lady',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );
      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: qwenResult),
        fallback: _FakeTranscriptionService(result: whisperResult),
      );

      final result = await service.transcribe(
        _request(
          tempDirectory.path,
          engineOrder: TranscriptionEngineOrder.whisperPrimary,
        ),
      );
      final metadata = result.lyrics.metadata;
      final candidates = metadata['fallbackCandidates'] as List;
      final candidate = Map<String, dynamic>.from(candidates.single as Map);

      expect(result.lyrics.lines.single.text, 'passion lady');
      expect(metadata['fallbackCandidateCount'], 1);
      expect(metadata['fallbackAppliedCount'], 0);
      expect(candidate['alternativeText'], 'Ashin lady');
      expect(candidate['reason'], 'engine_disagreement_review');

      await service.dispose();
    });

    test('uses Whisper primary and Qwen second opinion on Intel Mac', () async {
      final qwenResult = _result(
        LyricLine(
          text: 'yellow submarine',
          startTime: const Duration(milliseconds: 10100),
          endTime: const Duration(milliseconds: 12900),
          confidence: 92,
        ),
      );

      final whisperResult = _result(
        LyricLine(
          text: 'hello hello hello hello',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 13),
          confidence: 35,
        ),
      );

      final service = HighQualityTranscriptionService(
        primary: _FakeTranscriptionService(result: qwenResult),
        fallback: _FakeTranscriptionService(result: whisperResult),
      );

      final result = await service.transcribe(
        _request(
          tempDirectory.path,
          engineOrder: TranscriptionEngineOrder.whisperPrimary,
        ),
      );

      final line = result.lyrics.lines.single;
      expect(line.text, 'yellow submarine');
      expect(line.startTime, const Duration(seconds: 10));
      expect(line.endTime, const Duration(seconds: 13));
      expect(result.lyrics.metadata['primaryEngine'], 'whisper.cpp-large-v3');
      expect(result.lyrics.metadata['fallbackEngine'], 'qwen3-asr-0.6b');
      expect(result.lyrics.metadata['fallbackAppliedCount'], 1);

      await service.dispose();
    });
    test(
      'preserves a novel secondary lyric inside an overlapping primary segment '
      'for both engine orders',
      () async {
        final fullLine = LyricLine(
          text: 'we are dancing through the night',
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 14),
          confidence: 92,
        );
        final secondaryLines = [
          LyricLine(
            text: 'we are dancing',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(milliseconds: 11700),
            confidence: 92,
          ),
          LyricLine(
            text: 'sing a little song',
            startTime: const Duration(milliseconds: 11900),
            endTime: const Duration(milliseconds: 12300),
            confidence: 92,
          ),
          LyricLine(
            text: 'dancing',
            startTime: const Duration(milliseconds: 12350),
            endTime: const Duration(milliseconds: 12700),
            confidence: 92,
          ),
          LyricLine(
            text: 'through the night',
            startTime: const Duration(milliseconds: 12700),
            endTime: const Duration(milliseconds: 13900),
            confidence: 92,
          ),
        ];

        for (final engineOrder in [
          TranscriptionEngineOrder.qwenPrimary,
          TranscriptionEngineOrder.whisperPrimary,
        ]) {
          final qwenLines = engineOrder == TranscriptionEngineOrder.qwenPrimary
              ? [fullLine]
              : secondaryLines;
          final whisperLines =
              engineOrder == TranscriptionEngineOrder.qwenPrimary
              ? secondaryLines
              : [fullLine];
          final service = HighQualityTranscriptionService(
            primary: _FakeTranscriptionService(result: _resultLines(qwenLines)),
            fallback: _FakeTranscriptionService(
              result: _resultLines(whisperLines),
            ),
          );

          try {
            final result = await service.transcribe(
              _request(tempDirectory.path, engineOrder: engineOrder),
            );
            final lines = result.lyrics.lines;
            expect(lines.map((line) => line.text).toList(), [
              fullLine.text,
              'sing a little song',
              'dancing',
            ], reason: 'engine order: $engineOrder');
            expect(
              lines[1].confidence,
              60,
              reason: 'novel secondary lines must stay review-only',
            );
            expect(lines[2].confidence, 60);
            expect(result.lyrics.metadata['secondaryOnlyLineCount'], 2);
            expect(result.lyrics.metadata['secondaryOnlyLineIndices'], [1, 2]);
            expect(result.lyrics.metadata['fallbackCandidateCount'], 0);
          } finally {
            await service.dispose();
          }
        }
      },
    );
    test(
      'normalization timeout is an environment failure and removes partial WAV',
      () async {
        final input = File(
          '${tempDirectory.path}${Platform.pathSeparator}source.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 1));
        final process = _FakeProcess();
        final service = HighQualityTranscriptionService(
          primary: _FakeTranscriptionService(result: _resultLines([])),
          fallback: _FakeTranscriptionService(result: _resultLines([])),
          sharedAudioTimeoutForFile: (_) async =>
              const Duration(milliseconds: 20),
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, arguments) async {
              await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
              return process;
            },
            terminationGrace: const Duration(milliseconds: 5),
            streamDrainGrace: const Duration(milliseconds: 5),
          ),
        );
        final outputPath =
            '${tempDirectory.path}${Platform.pathSeparator}'
            'high_quality_shared_input.wav';

        await expectLater(
          service.transcribe(
            _request(
              tempDirectory.path,
              includeNormalizedInput: false,
              inputAudioPath: input.path,
            ),
          ),
          throwsA(
            isA<TranscriptionException>()
                .having(
                  (error) => error.kind,
                  'failure kind',
                  TranscriptionFailureKind.environment,
                )
                .having((error) => error.message, 'message', contains('超时')),
          ),
        );

        expect(await File(outputPath).exists(), isFalse);
        expect(process.killSignals, contains(ProcessSignal.sigterm));
        await service.dispose();
      },
    );

    test(
      'cancelling shared normalization escalates and removes partial WAV',
      () async {
        final input = File(
          '${tempDirectory.path}${Platform.pathSeparator}source.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 1));
        final process = _FakeProcess(killOnSigterm: false, killOnSigkill: true);
        final started = Completer<void>();
        final primary = _FakeTranscriptionService(result: _resultLines([]));
        final fallback = _FakeTranscriptionService(result: _resultLines([]));
        final service = HighQualityTranscriptionService(
          primary: primary,
          fallback: fallback,
          sharedAudioTimeoutForFile: (_) async => const Duration(minutes: 1),
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, arguments) async {
              await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
              if (!started.isCompleted) started.complete();
              return process;
            },
            terminationGrace: const Duration(milliseconds: 10),
            streamDrainGrace: const Duration(milliseconds: 10),
          ),
        );
        final outputPath =
            '${tempDirectory.path}${Platform.pathSeparator}'
            'high_quality_shared_input.wav';
        final running = service.transcribe(
          _request(
            tempDirectory.path,
            includeNormalizedInput: false,
            inputAudioPath: input.path,
          ),
        );
        await started.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await service.cancel();

        await expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.message,
              'message',
              '歌词识别已取消',
            ),
          ),
        );
        expect(await File(outputPath).exists(), isFalse);
        expect(process.killSignals, contains(ProcessSignal.sigterm));
        expect(process.killSignals, contains(ProcessSignal.sigkill));
        expect(primary.requests, isEmpty);
        expect(fallback.requests, isEmpty);
        await service.dispose();
      },
    );
  });
}

TranscriptionRequest _request(
  String outputDirectory, {
  TranscriptionEngineOrder engineOrder = TranscriptionEngineOrder.qwenPrimary,
  String? qwenModelPath,
  String? qwenAlignerModelPath,
  String? whisperModelPath,
  bool includeNormalizedInput = true,
  String inputAudioPath = 'unused-by-fake.wav',
}) {
  return TranscriptionRequest(
    inputAudioPath: inputAudioPath,
    normalizedInputAudioPath: includeNormalizedInput
        ? 'already-normalized.wav'
        : null,
    outputDirectory: outputDirectory,
    config: TranscriptionConfig(
      mode: TranscriptionMode.highestQuality,
      engineOrder: engineOrder,
      qwenExecutable: 'qwen3-asr',
      qwenModelPath:
          qwenModelPath ??
          (engineOrder == TranscriptionEngineOrder.whisperPrimary
              ? 'Qwen/Qwen3-ASR-0.6B'
              : 'Qwen/Qwen3-ASR-1.7B'),
      qwenAlignerModelPath:
          qwenAlignerModelPath ?? 'Qwen/Qwen3-ForcedAligner-0.6B',
      whisperExecutable: 'whisper-cli',
      modelPath: whisperModelPath ?? 'ggml-large-v3.bin',
    ),
  );
}

TranscriptionResult _result(LyricLine line) => _resultLines([line]);

TranscriptionResult _resultLines(List<LyricLine> lines) {
  return TranscriptionResult(
    lyrics: LyricDocument(
      language: 'auto',
      lines: lines,
      metadata: const {'draft': true},
    ),
    normalizedAudioPath: 'normalized.wav',
    rawJsonPath: 'result.json',
    detectedLanguage: 'auto',
  );
}

class _FakeTranscriptionService implements TranscriptionService {
  final TranscriptionResult? result;
  final TranscriptionException? error;
  final List<TranscriptionRequest> requests = [];
  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  _FakeTranscriptionService({this.result, this.error});

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _progressController.stream;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    requests.add(request);
    final failure = error;
    if (failure != null) throw failure;

    final value = result;
    if (value == null) {
      throw const TranscriptionException('Fake result not configured');
    }
    return value;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _progressController.close();
  }
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final bool killOnSigterm;
  final bool killOnSigkill;

  _FakeProcess({this.killOnSigterm = true, this.killOnSigkill = true});

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if ((signal == ProcessSignal.sigterm && killOnSigterm) ||
        (signal == ProcessSignal.sigkill && killOnSigkill)) {
      finish(137);
    }
    return true;
  }

  void finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    unawaited(_closeStreams());
  }

  Future<void> _closeStreams() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}
