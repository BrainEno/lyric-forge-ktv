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
    test('short audio delegates without chunking after a bounded probe', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-short-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
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

      final result = await service.transcribe(_request(input.path, directory.path));

      expect(result.detectedLanguage, 'en');
      expect(delegate.calls, 1);
      await service.dispose();
    });

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

    test('cancelling a stuck duration probe escalates and stays typed', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-cancel-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final process = _FakeProcess(
        killOnSigterm: false,
        killOnSigkill: true,
      );
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
      final running = service.transcribe(_request(input.path, directory.path));
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
    });

    test(
      'failed chunk extraction removes partial WAV but preserves completed checkpoints',
      () async {
        final directory = await Directory.systemTemp.createTemp('chunk-checkpoint-');
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}${Platform.pathSeparator}song.wav');
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
            'version': 1,
            'sourceFingerprint': fingerprint,
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
        expect(
          jsonDecode(await manifestFile.readAsString())['completed'],
          ['chunk_0000'],
        );
        expect(
          await File(
            '${chunksDir.path}${Platform.pathSeparator}chunk_0001.wav',
          ).exists(),
          isFalse,
        );
        await service.dispose();
      },
    );
  });
}

TranscriptionRequest _request(String inputPath, String outputDirectory) =>
    TranscriptionRequest(
      inputAudioPath: inputPath,
      outputDirectory: outputDirectory,
      config: const TranscriptionConfig(
        whisperExecutable: 'whisper',
        modelPath: 'model.bin',
      ),
    );

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
      rawJsonPath: '${request.outputDirectory}${Platform.pathSeparator}raw.json',
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
