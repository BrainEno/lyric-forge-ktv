import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_runtime_session.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

import 'fake_qwen_runtime.dart';

void main() {
  group('Qwen3AsrNativeTranscriptionService runtime session lifecycle', () {
    late Directory tempDirectory;
    late FakeQwenRuntime runtime;
    late List<ImpostorServer> impostors;
    late List<TranscriptionProgress> progress;
    Qwen3AsrNativeTranscriptionService? service;
    StreamSubscription<TranscriptionProgress>? progressSubscription;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'lyric_forge_qwen_session_',
      );
      impostors = <ImpostorServer>[];
      progress = <TranscriptionProgress>[];
      runtime = FakeQwenRuntime();
    });

    tearDown(() async {
      await progressSubscription?.cancel();
      progressSubscription = null;
      await service?.dispose();
      service = null;
      await runtime.dispose();
      for (final impostor in impostors) {
        await impostor.close();
      }
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    Future<File> touch(String name, {int bytes = 1}) async {
      final file = File('${tempDirectory.path}/$name');
      await file.writeAsBytes(List<int>.filled(bytes, 0));
      return file;
    }

    Future<TranscriptionConfig> config({String model = 'qwen-model'}) async {
      final qwen = await touch('qwen3-asr');
      final ffmpeg = await touch('ffmpeg');
      final qwenModel = await touch('$model.bin');
      final aligner = await touch('aligner-model.bin');
      return TranscriptionConfig(
        qwenExecutable: qwen.path,
        qwenModelPath: qwenModel.path,
        qwenAlignerModelPath: aligner.path,
        ffmpegExecutable: ffmpeg.path,
        whisperExecutable: 'unused-whisper',
        modelPath: 'unused-whisper-model',
      );
    }

    Future<TranscriptionRequest> request(TranscriptionConfig config) async {
      final input = await touch('input.mp3', bytes: 3);
      // Pre-normalized 2 s PCM WAV, so no FFmpeg run is needed.
      final normalized = await touch('normalized.wav', bytes: 44 + 64000);
      return TranscriptionRequest(
        inputAudioPath: input.path,
        normalizedInputAudioPath: normalized.path,
        outputDirectory: '${tempDirectory.path}/output',
        config: config,
        context: 'secret lyric context',
      );
    }

    Qwen3AsrNativeTranscriptionService build({
      Duration startupTimeout = const Duration(seconds: 5),
      Duration idleShutdownDelay = const Duration(minutes: 10),
    }) {
      final supervisor = AsrProcessSupervisor(
        startProcess: (executable, arguments) async =>
            FakeToolProcess(arguments),
        terminationGrace: const Duration(milliseconds: 20),
        streamDrainGrace: const Duration(milliseconds: 20),
      );
      final created = Qwen3AsrNativeTranscriptionService(
        processSupervisor: supervisor,
        runtimeLauncher: QwenRuntimeLauncher(
          startProcess: runtime.start,
          supervisor: supervisor,
          pollInterval: const Duration(milliseconds: 10),
          identityAttempts: 3,
          identityRetryDelay: const Duration(milliseconds: 20),
          identityTimeout: const Duration(seconds: 1),
        ),
        runtimeStartupTimeout: startupTimeout,
        idleShutdownDelay: idleShutdownDelay,
      );
      progressSubscription = created.progressStream.listen(progress.add);
      service = created;
      return created;
    }

    Future<List<String>> align(
      Qwen3AsrNativeTranscriptionService service,
      TranscriptionConfig config,
    ) async {
      final audio = await touch('reference.mp3', bytes: 3);
      final spans = await service.alignReference(
        audioPath: audio.path,
        text: 'hello world',
        language: 'English',
        audioDuration: const Duration(seconds: 2),
        config: config,
      );
      return spans.map((span) => span.text).toList();
    }

    Matcher failure(TranscriptionFailureKind kind) => throwsA(
      isA<TranscriptionException>().having((error) => error.kind, 'kind', kind),
    );

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 60));

    test('consecutive tasks reuse one re-verified session', () async {
      final service = build();
      final qwenConfig = await config();

      final first = await service.transcribe(await request(qwenConfig));
      final second = await service.transcribe(await request(qwenConfig));

      expect(first.lyrics.lines.single.text, 'hello world');
      expect(second.lyrics.lines.single.text, 'hello world');
      expect(runtime.launches, hasLength(1));
      final process = runtime.launches.single;
      final transcribes = process.requestsTo('/v1/transcribe').toList();
      expect(transcribes, hasLength(2));
      expect(transcribes.every((request) => request.authorized), isTrue);
      // Startup proof plus one signed re-check before the reused session.
      expect(process.requestsTo('/healthz'), hasLength(2));
      expect(process.requests.every((request) => request.authorized), isTrue);
      expect(service.isRunning, isFalse);
      expect(service.hasRuntimeSession, isTrue);
    });

    test(
      'transcription and alignment share the authenticated runtime',
      () async {
        final service = build();
        final qwenConfig = await config();

        await service.transcribe(await request(qwenConfig));
        expect(await align(service, qwenConfig), ['hello', 'world']);
        await service.transcribe(await request(qwenConfig));

        expect(runtime.launches, hasLength(1));
        final process = runtime.launches.single;
        final alignRequest = process.requestsTo('/v1/align').single;
        expect(alignRequest.authorized, isTrue);
        final alignedAudio = RegExp(r'"audio":"([^"]+)"')
            .firstMatch(alignRequest.body)!
            .group(1)!;
        expect(
          await File(alignedAudio.replaceAll(r'\\', r'\')).exists(),
          isFalse,
          reason: 'temporary normalized alignment audio must be removed',
        );
        expect(service.isRunning, isFalse);
      },
    );

    test('a concurrent start is refused without a second runtime', () async {
      runtime = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(
          transcribeDelay: const Duration(milliseconds: 300),
        ),
      );
      final service = build();
      final qwenConfig = await config();

      final running = service.transcribe(await request(qwenConfig));
      await expectLater(
        service.transcribe(await request(qwenConfig)),
        failure(TranscriptionFailureKind.busy),
      );
      await expectLater(
        align(service, qwenConfig),
        failure(TranscriptionFailureKind.busy),
      );
      await running;

      expect(runtime.launches, hasLength(1));
      expect(service.isRunning, isFalse);
    });

    test('cancel during startup stops the runtime and clears state', () async {
      runtime = FakeQwenRuntime(
        behaviorFor: (index) => FakeRuntimeBehavior(announce: index > 0),
      );
      final service = build();
      final qwenConfig = await config();

      final running = service.transcribe(await request(qwenConfig));
      while (runtime.launches.isEmpty ||
          runtime.launches.first.secretLine == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Listen before cancelling: the aborted task fails immediately.
      final outcome = expectLater(
        running,
        failure(TranscriptionFailureKind.cancelled),
      );
      await service.cancel();
      await outcome;
      await settle();

      expect(runtime.launches.first.exited, isTrue);
      expect(runtime.launches.first.requestsTo('/v1/transcribe'), isEmpty);
      expect(service.hasRuntimeSession, isFalse);
      expect(service.isRunning, isFalse);

      // The next task gets a brand-new process and secret.
      await service.transcribe(await request(qwenConfig));
      expect(runtime.launches, hasLength(2));
      expect(
        runtime.launches[1].secretLine,
        isNot(runtime.launches[0].secretLine),
      );
    });

    test('cancel during inference stops the runtime and its secret', () async {
      runtime = FakeQwenRuntime(
        behaviorFor: (_) =>
            FakeRuntimeBehavior(transcribeDelay: const Duration(seconds: 5)),
      );
      final service = build();
      final qwenConfig = await config();

      final running = service.transcribe(await request(qwenConfig));
      final process = await () async {
        while (runtime.launches.isEmpty ||
            runtime.launches.first.requestsTo('/v1/transcribe').isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return runtime.launches.first;
      }().timeout(const Duration(seconds: 5));
      // The request is recorded only once the full body arrived; the fake
      // is now sleeping inside inference.
      // Listen before cancelling: the aborted task fails immediately.
      final outcome = expectLater(
        running,
        failure(TranscriptionFailureKind.cancelled),
      );
      await service.cancel();
      await outcome;
      await settle();

      expect(process.exited, isTrue);
      expect(service.hasRuntimeSession, isFalse);
      expect(service.isRunning, isFalse);
      expect(
        await File('${tempDirectory.path}/output/qwen3_asr_result.json')
            .exists(),
        isFalse,
      );
    });

    test('a crashed runtime is replaced with a fresh session', () async {
      final service = build();
      final qwenConfig = await config();

      await service.transcribe(await request(qwenConfig));
      final first = runtime.launches.single;
      await first.crash();
      await settle();
      await service.transcribe(await request(qwenConfig));

      expect(runtime.launches, hasLength(2));
      expect(runtime.launches[1].secretLine, isNot(first.secretLine));
      expect(
        runtime.launches[1].requestsTo('/v1/transcribe').single.authorized,
        isTrue,
      );
    });

    test('idle shutdown closes the runtime and its control pipe', () async {
      final service = build(
        idleShutdownDelay: const Duration(milliseconds: 50),
      );
      await service.transcribe(await request(await config()));
      final process = runtime.launches.single;

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(process.stdinClosed, isTrue);
      expect(process.exited, isTrue);
      expect(service.hasRuntimeSession, isFalse);
    });

    test('a config change restarts the runtime with a new secret', () async {
      final service = build();

      await service.transcribe(await request(await config()));
      await service.transcribe(await request(await config(model: 'other')));

      expect(runtime.launches, hasLength(2));
      expect(runtime.launches[0].exited, isTrue);
      expect(
        runtime.launches[0].secretLine,
        isNot(runtime.launches[1].secretLine),
      );
      expect(runtime.launches[1].arguments.join(' '), contains('other.bin'));
    });

    test(
      'an unsigned inference response is discarded and stops the runtime',
      () async {
        runtime = FakeQwenRuntime(
          behaviorFor: (_) =>
              FakeRuntimeBehavior(responseProof: FakeProofMode.missing),
        );
        final service = build();

        await expectLater(
          service.transcribe(await request(await config())),
          failure(TranscriptionFailureKind.environment),
        );
        await settle();

        expect(runtime.launches.single.exited, isTrue);
        expect(service.hasRuntimeSession, isFalse);
        expect(
          await File('${tempDirectory.path}/output/qwen3_asr_result.json')
              .exists(),
          isFalse,
          reason: 'an unproven body must never be persisted',
        );
      },
    );

    test(
      'a dropped connection fails the task without a stuck busy flag',
      () async {
        runtime = FakeQwenRuntime(
          behaviorFor: (index) =>
              FakeRuntimeBehavior(dropTranscribeConnection: index == 0),
        );
        final service = build();
        final qwenConfig = await config();

        await expectLater(
          service.transcribe(await request(qwenConfig)),
          failure(TranscriptionFailureKind.environment),
        );
        expect(service.isRunning, isFalse);

        runtime.launches.single.behavior.dropTranscribeConnection = false;
        final result = await service.transcribe(await request(qwenConfig));
        expect(result.lyrics.lines, isNotEmpty);
      },
    );

    test('a hijacked port never receives the audio path or lyrics', () async {
      final impostor = await ImpostorServer.start();
      impostors.add(impostor);
      runtime = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(announcedPort: impostor.port),
      );
      final service = build();
      final qwenConfig = await config();

      await expectLater(
        service.transcribe(await request(qwenConfig)),
        failure(TranscriptionFailureKind.environment),
      );
      await expectLater(
        align(service, qwenConfig),
        failure(TranscriptionFailureKind.environment),
      );

      expect(impostor.requests.map((r) => r.path).toSet(), {'/healthz'});
      for (final received in impostor.requests) {
        expect(received.body, isEmpty);
        expect(received.body, isNot(contains('normalized.wav')));
        expect(received.body, isNot(contains('secret lyric context')));
      }
      expect(runtime.launches.every((process) => process.exited), isTrue);
      expect(service.hasRuntimeSession, isFalse);
      expect(service.isRunning, isFalse);
    });

    test('an unpatched runtime fails closed with an update hint', () async {
      runtime = FakeQwenRuntime(
        behaviorFor: (_) => FakeRuntimeBehavior(
          exitBeforeReadyCode: 2,
          stderrBeforeExit: [
            "error: unexpected argument '--lyricforge-session-stdin' found",
          ],
        ),
      );
      final service = build();

      await expectLater(
        service.transcribe(await request(await config())),
        throwsA(
          isA<TranscriptionException>()
              .having(
                (error) => error.kind,
                'kind',
                TranscriptionFailureKind.environment,
              )
              .having((error) => error.message, 'message', contains('会话认证')),
        ),
      );
    });

    test('the session secret never reaches argv, progress or errors', () async {
      runtime = FakeQwenRuntime(
        behaviorFor: (index) => FakeRuntimeBehavior(
          echoSecretToStderr: true,
          exitBeforeReadyCode: index == 0 ? 1 : null,
          stderrBeforeExit: const ['model load failed'],
        ),
      );
      final service = build();
      final qwenConfig = await config();

      TranscriptionException? startupError;
      try {
        await service.transcribe(await request(qwenConfig));
      } on TranscriptionException catch (error) {
        startupError = error;
      }
      await service.transcribe(await request(qwenConfig));

      final secrets = runtime.launches.map((p) => p.secretLine!).toList();
      expect(secrets, hasLength(2));
      final visible = <String>[
        startupError.toString(),
        startupError?.details ?? '',
        ...progress.map((event) => event.message),
        for (final launch in runtime.launches) launch.arguments.join(' '),
        await File('${tempDirectory.path}/output/qwen3_asr_result.json')
            .readAsString(),
      ];
      for (final secret in secrets) {
        for (final text in visible) {
          expect(text, isNot(contains(secret)));
        }
      }
      expect(startupError?.details, contains('model load failed'));
    });

    test('dispose stops an idle runtime and revokes its session', () async {
      final service = build();
      await service.transcribe(await request(await config()));
      final process = runtime.launches.single;

      await service.dispose();

      expect(process.exited, isTrue);
      expect(process.stdinClosed || process.killSignals.isNotEmpty, isTrue);
    });
  });
}
