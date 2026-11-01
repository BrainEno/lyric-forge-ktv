import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  group('ResumableChunkedTranscriptionService', () {
    test(
      'short audio delegates without chunking after a bounded probe',
      () async {
        final directory = await Directory.systemTemp.createTemp('chunk-short-');
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final delegate = _FakeService();
        final process = _FakeProcess();
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, arguments) async {
              expect(arguments, contains('-t'));
              Timer(const Duration(milliseconds: 1), () {
                process.emitStderr(
                  'Duration: 00:01:00.000, start: 0.000000, bitrate: 1 kb/s',
                );
                process.finish(0);
              });
              return process;
            },
          ),
        );

        final result = await service.transcribe(
          _request(input.path, directory.path),
        );

        expect(result.detectedLanguage, 'en');
        expect(delegate.calls, 1);
        await service.dispose();
      },
    );

    test('constructor accepts retry and overlap policy', () async {
      final delegate = _FakeService();
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 2),
        overlap: const Duration(seconds: 6),
        maxAttempts: 2,
      );
      expect(service.isRunning, isFalse);
      await service.dispose();
    });

    test('duration probe timeout is a blocking environment failure', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-timeout-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final process = _FakeProcess();
      final service = ResumableChunkedTranscriptionService(
        delegate: _FakeService(),
        durationProbeTimeout: const Duration(milliseconds: 20),
        processSupervisor: AsrProcessSupervisor(
          startProcess: (_, __) async => process,
          terminationGrace: const Duration(milliseconds: 5),
          streamDrainGrace: const Duration(milliseconds: 5),
        ),
      );

      await expectLater(
        service.transcribe(_request(input.path, directory.path)),
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

      expect(process.killSignals, contains(ProcessSignal.sigterm));
      await service.dispose();
    });

    test(
      'cancelling a stuck duration probe escalates and stays typed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-cancel-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final process = _FakeProcess(killOnSigterm: false, killOnSigkill: true);
        final started = Completer<void>();
        final service = ResumableChunkedTranscriptionService(
          delegate: _FakeService(),
          durationProbeTimeout: const Duration(minutes: 1),
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, __) async {
              if (!started.isCompleted) started.complete();
              return process;
            },
            terminationGrace: const Duration(milliseconds: 10),
            streamDrainGrace: const Duration(milliseconds: 10),
          ),
        );
        final running = service.transcribe(
          _request(input.path, directory.path),
        );
        await started.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await service.cancel();

        await expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'failure kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        expect(process.killSignals, contains(ProcessSignal.sigterm));
        expect(process.killSignals, contains(ProcessSignal.sigkill));
        await service.dispose();
      },
    );

    test(
      'failed chunk extraction removes partial WAV but preserves completed checkpoints',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-checkpoint-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(256, 7));
        final stat = await input.stat();
        final fingerprint =
            '${stat.size}:${stat.modified.toUtc().millisecondsSinceEpoch}:${input.absolute.path}';
        final chunksDir = Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session'
          '${Platform.pathSeparator}chunks',
        );
        await chunksDir.create(recursive: true);
        final manifestFile = File(
          '${directory.path}${Platform.pathSeparator}chunk_session'
          '${Platform.pathSeparator}session.json',
        );
        await manifestFile.writeAsString(
          jsonEncode({
            'version':
                ResumableChunkedTranscriptionService.checkpointManifestVersion,
            'sourceFingerprint': fingerprint,
            'configFingerprint':
                ResumableChunkedTranscriptionService.checkpointConfigFingerprint(
                  _config(),
                ),
            'chunkMs': const Duration(minutes: 3).inMilliseconds,
            'overlapMs': const Duration(seconds: 8).inMilliseconds,
            'durationMs': const Duration(minutes: 4).inMilliseconds,
            'completed': ['chunk_0000'],
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        final completedCheckpoint = File(
          '${chunksDir.path}${Platform.pathSeparator}chunk_0000.json',
        );
        await completedCheckpoint.writeAsString('{}');

        final supervisor = AsrProcessSupervisor(
          startProcess: (_, arguments) async {
            final process = _FakeProcess();
            if (arguments.contains('-ss')) {
              await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
              Timer(const Duration(milliseconds: 1), () => process.finish(23));
            } else {
              Timer(const Duration(milliseconds: 1), () {
                process.emitStderr(
                  'Duration: 00:04:00.000, start: 0.000000, bitrate: 1 kb/s',
                );
                process.finish(0);
              });
            }
            return process;
          },
          streamDrainGrace: const Duration(milliseconds: 10),
        );
        final service = ResumableChunkedTranscriptionService(
          delegate: _FakeService(),
          chunkDuration: const Duration(minutes: 3),
          processSupervisor: supervisor,
        );

        await expectLater(
          service.transcribe(_request(input.path, directory.path)),
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'failure kind',
              TranscriptionFailureKind.input,
            ),
          ),
        );

        expect(await completedCheckpoint.exists(), isTrue);
        expect(jsonDecode(await manifestFile.readAsString())['completed'], [
          'chunk_0000',
        ]);
        expect(
          await File(
            '${chunksDir.path}${Platform.pathSeparator}chunk_0001.wav',
          ).exists(),
          isFalse,
        );
        await service.dispose();
      },
    );

    test('a five-minute song is recognised in one pass', () async {
      expect(
        ResumableChunkedTranscriptionService.defaultChunkDuration,
        const Duration(minutes: 20),
      );
      final directory = await Directory.systemTemp.createTemp('chunk-song-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final delegate = _FakeService();
      final ffmpeg = _FfmpegStub(durationLabel: '00:05:00.000');
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        processSupervisor: ffmpeg.supervisor,
      );

      final result = await service.transcribe(
        _request(input.path, directory.path),
      );

      expect(delegate.calls, 1);
      expect(ffmpeg.chunkStartRequests, 0);
      expect(
        Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session',
        ).existsSync(),
        isFalse,
      );
      expect(result.lyrics.metadata['chunked'], isNull);
      await service.dispose();
    });

    test('chunk merge keeps engine identity and remaps indices', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-merge-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
      final delegate = _ScriptedService(
        (chunk) => chunk == 0
            ? const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'first line',
                    startTime: Duration.zero,
                    endTime: Duration(seconds: 5),
                  ),
                  LyricLine(
                    text: 'second line',
                    startTime: Duration(milliseconds: 175000),
                    endTime: Duration(milliseconds: 179000),
                    confidence: 80,
                  ),
                ],
                metadata: {
                  'qualityMode': 'highestQuality',
                  'primaryEngine': 'qwen3-asr-1.7b',
                  'fallbackCandidates': [
                    {'lineIndex': 1, 'primaryText': 'second line'},
                  ],
                  'secondaryOnlyLineIndices': [1],
                  'suspiciousLineIndexes': [0],
                  'fallbackAppliedCount': 1,
                  'qwenRawJsonPath': '/tmp/chunk_0000/qwen.json',
                },
              )
            : const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'second line',
                    startTime: Duration(seconds: 3),
                    endTime: Duration(seconds: 7),
                    confidence: 90,
                  ),
                  LyricLine(
                    text: 'third line',
                    startTime: Duration(seconds: 60),
                    endTime: Duration(seconds: 64),
                  ),
                ],
                metadata: {
                  'qualityMode': 'highestQuality',
                  'primaryEngine': 'qwen3-asr-1.7b',
                  'fallbackCandidates': [
                    {
                      'lineIndex': 1,
                      'primaryText': 'third line',
                      'startMs': 60000,
                      'endMs': 64000,
                    },
                  ],
                  'secondaryOnlyLineIndices': [1],
                  'suspiciousLineIndexes': [1],
                  'fallbackAppliedCount': 0,
                },
              ),
      );
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 3),
        processSupervisor: ffmpeg.supervisor,
      );

      final result = await service.transcribe(
        _request(input.path, directory.path),
      );

      final metadata = result.lyrics.metadata;
      expect(result.lyrics.lines.map((line) => line.text).toList(), [
        'first line',
        'second line',
        'third line',
      ]);
      // The overlap duplicate keeps the more confident copy.
      expect(result.lyrics.lines[1].confidence, 90);
      // Engine identity and quality mode survive the merge (they used to be
      // replaced by a lone mergeStrategy key, which also broke model tracing).
      expect(metadata['primaryEngine'], 'qwen3-asr-1.7b');
      expect(metadata['qualityMode'], 'highestQuality');
      expect(metadata['mergeStrategy'], 'overlapTextAndTimeDedup');
      // Indices follow the merged line list: the second chunk's line 1 became
      // merged line 2 after its first line deduplicated into merged line 1.
      expect(metadata['secondaryOnlyLineIndices'], [1, 2]);
      expect(metadata['secondaryOnlyLineCount'], 2);
      expect(metadata['suspiciousLineIndexes'], [0, 2]);
      expect(metadata['fallbackAppliedCount'], 1);
      expect(metadata['fallbackCandidateCount'], 2);
      expect(
        (metadata['fallbackCandidates'] as List)
            .map((candidate) => (candidate as Map)['lineIndex'])
            .toList(),
        [1, 2],
      );
      // Candidate timestamps must describe the song, not the chunk's local time.
      expect(
        (metadata['fallbackCandidates'] as List).last,
        containsPair('startMs', 232000),
      );
      // A single chunk's artifact path would be a lie about the merged result.
      expect(metadata.containsKey('qwenRawJsonPath'), isFalse);
      expect(metadata['chunked'], isTrue);
      expect(metadata['chunkCount'], 2);
      await service.dispose();
    });

    test('changing recognition settings invalidates checkpoints', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-config-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final delegate = _FakeService();
      final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 3),
        processSupervisor: ffmpeg.supervisor,
      );

      await service.transcribe(
        _request(input.path, directory.path, config: _config()),
      );
      expect(delegate.calls, 2);

      // Identical settings resume instead of rerunning inference.
      await service.transcribe(
        _request(input.path, directory.path, config: _config()),
      );
      expect(delegate.calls, 2);

      // A different model must not replay the previous run's lyrics.
      await service.transcribe(
        _request(
          input.path,
          directory.path,
          config: _config(modelPath: 'large-v3.bin'),
        ),
      );
      expect(delegate.calls, 4);
      await service.dispose();
    });
  });
}

TranscriptionConfig _config({String modelPath = 'model.bin'}) =>
    TranscriptionConfig(whisperExecutable: 'whisper', modelPath: modelPath);

TranscriptionRequest _request(
  String inputPath,
  String outputDirectory, {
  TranscriptionConfig? config,
}) => TranscriptionRequest(
  inputAudioPath: inputPath,
  outputDirectory: outputDirectory,
  config: config ?? _config(),
);

/// Reports a fixed duration for whichever file FFmpeg is asked about and
/// materialises chunk WAVs like the real extractor.
class _FfmpegStub {
  _FfmpegStub({required this.durationLabel});

  final String durationLabel;
  int chunkStartRequests = 0;

  AsrProcessSupervisor get supervisor => AsrProcessSupervisor(
    startProcess: (_, arguments) async {
      final process = _FakeProcess();
      if (arguments.contains('-ss')) {
        chunkStartRequests++;
        await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
        Timer(const Duration(milliseconds: 1), () => process.finish(0));
      } else {
        Timer(const Duration(milliseconds: 1), () {
          process.emitStderr(
            'Duration: $durationLabel, start: 0.000000, bitrate: 1 kb/s',
          );
          process.finish(0);
        });
      }
      return process;
    },
    streamDrainGrace: const Duration(milliseconds: 10),
  );
}

/// Returns a scripted document per chunk working directory.
class _ScriptedService implements TranscriptionService {
  _ScriptedService(this.documentsForChunk);

  final LyricDocument Function(int chunkIndex) documentsForChunk;
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  final List<String> outputDirectories = <String>[];

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final chunkIndex = outputDirectories.length;
    outputDirectories.add(request.outputDirectory);
    final document = documentsForChunk(chunkIndex);
    return TranscriptionResult(
      lyrics: document,
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath:
          '${request.outputDirectory}${Platform.pathSeparator}raw.json',
      detectedLanguage: document.language,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeService implements TranscriptionService {
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls++;
    return TranscriptionResult(
      lyrics: const LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'hello',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath:
          '${request.outputDirectory}${Platform.pathSeparator}raw.json',
      detectedLanguage: 'en',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
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

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

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
