import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  group('Qwen3AsrNativeTranscriptionService process lifecycle', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'lyric_forge_qwen_lifecycle_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    Future<File> touch(String name) async {
      final file = File('${tempDirectory.path}/$name');
      await file.writeAsBytes([1]);
      return file;
    }

    test(
      'cancellation escalates through the supervised FFmpeg process',
      () async {
        final input = File('${tempDirectory.path}/input.mp3');
        await input.writeAsBytes([1, 2, 3]);
        final qwenExecutable = await touch('qwen-runtime');
        final ffmpegExecutable = await touch('ffmpeg');
        final qwenModel = await touch('qwen-model.bin');
        final alignerModel = await touch('aligner-model.bin');
        final process = _FakeProcess(killOnSigterm: false, killOnSigkill: true);
        final processStarted = Completer<void>();
        final supervisor = AsrProcessSupervisor(
          startProcess: (_, __) async {
            if (!processStarted.isCompleted) processStarted.complete();
            return process;
          },
          terminationGrace: const Duration(milliseconds: 10),
          streamDrainGrace: const Duration(milliseconds: 10),
        );
        final service = Qwen3AsrNativeTranscriptionService(
          processSupervisor: supervisor,
        );
        final outputDirectory = Directory('${tempDirectory.path}/output');
        final request = TranscriptionRequest(
          inputAudioPath: input.path,
          outputDirectory: outputDirectory.path,
          config: TranscriptionConfig(
            qwenExecutable: qwenExecutable.path,
            qwenModelPath: qwenModel.path,
            qwenAlignerModelPath: alignerModel.path,
            ffmpegExecutable: ffmpegExecutable.path,
            whisperExecutable: 'unused-whisper',
            modelPath: 'unused-whisper-model',
          ),
        );

        try {
          final running = service.transcribe(request);
          await processStarted.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 10));
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
          expect(
            await File(
              '${outputDirectory.path}${Platform.pathSeparator}'
              'qwen_transcription_input.wav',
            ).exists(),
            isFalse,
            reason: 'cancelled preprocessing must not leave a partial WAV',
          );
        } finally {
          await service.dispose();
        }
      },
    );

    test('Qwen request budget scales with normalized WAV duration', () {
      const bytesPerSecond = 16000 * 2;
      const wavHeaderBytes = 44;
      final short = AsrProcessTimeoutPolicy.qwenInferenceForPcmWavBytes(
        wavHeaderBytes + bytesPerSecond * 10,
      );
      final long = AsrProcessTimeoutPolicy.qwenInferenceForPcmWavBytes(
        wavHeaderBytes + bytesPerSecond * 60 * 10,
      );
      final veryLong = AsrProcessTimeoutPolicy.qwenInferenceForPcmWavBytes(
        wavHeaderBytes + bytesPerSecond * 60 * 180,
      );

      expect(short, const Duration(minutes: 5));
      expect(long, greaterThan(short));
      expect(veryLong, const Duration(minutes: 120));
    });

  });
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

  void finish(int code, {bool closeStreams = true}) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    if (closeStreams) unawaited(closeStreamsAsync());
  }

  Future<void> closeStreamsAsync() async {
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
