import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen3_asr_native_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_cpp_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  test('Whisper treats missing source as input failure', () async {
    final root = await Directory.systemTemp.createTemp(
      'lyricforge-whisper-input-',
    );
    addTearDown(() => root.delete(recursive: true));
    final service = WhisperCppTranscriptionService();
    addTearDown(service.dispose);

    await expectLater(
      service.transcribe(
        _request(
          input: '${root.path}${Platform.pathSeparator}missing.wav',
          output: root.path,
          config: _whisperConfig(modelPath: 'missing-model.bin'),
        ),
      ),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.input,
        ),
      ),
    );
  });

  test(
    'Whisper treats missing managed model and executable as environment',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-whisper-env-',
      );
      addTearDown(() => root.delete(recursive: true));
      final input = File('${root.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes([1, 2, 3]);

      final missingModelService = WhisperCppTranscriptionService();
      addTearDown(missingModelService.dispose);
      await expectLater(
        missingModelService.transcribe(
          _request(
            input: input.path,
            output: root.path,
            config: _whisperConfig(
              modelPath: '${root.path}${Platform.pathSeparator}missing.bin',
            ),
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.environment,
          ),
        ),
      );

      final model = File('${root.path}${Platform.pathSeparator}model.bin');
      await model.writeAsBytes([4]);
      final missingExecutableService = WhisperCppTranscriptionService();
      addTearDown(missingExecutableService.dispose);
      await expectLater(
        missingExecutableService.transcribe(
          _request(
            input: input.path,
            output: root.path,
            config: _whisperConfig(
              modelPath: model.path,
              whisperExecutable:
                  '${root.path}${Platform.pathSeparator}missing-whisper',
            ),
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.environment,
          ),
        ),
      );
    },
  );

  test('Qwen separates missing source from missing runtime', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-qwen-kind-');
    addTearDown(() => root.delete(recursive: true));

    final missingInputService = Qwen3AsrNativeTranscriptionService();
    addTearDown(missingInputService.dispose);
    await expectLater(
      missingInputService.transcribe(
        _request(
          input: '${root.path}${Platform.pathSeparator}missing.wav',
          output: root.path,
          config: _qwenConfig(qwenExecutable: 'qwen3-asr'),
        ),
      ),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.input,
        ),
      ),
    );

    final input = File('${root.path}${Platform.pathSeparator}song.wav');
    await input.writeAsBytes([1, 2, 3]);
    final missingRuntimeService = Qwen3AsrNativeTranscriptionService();
    addTearDown(missingRuntimeService.dispose);
    await expectLater(
      missingRuntimeService.transcribe(
        _request(
          input: input.path,
          output: root.path,
          config: _qwenConfig(
            qwenExecutable: '${root.path}${Platform.pathSeparator}missing-qwen',
          ),
        ),
      ),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.environment,
        ),
      ),
    );
  });

  test(
    'chunking immediately propagates environment failures without retrying',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-chunk-env-',
      );
      addTearDown(() => root.delete(recursive: true));
      final fakeFfmpeg = await _fakeFfmpeg(root);
      final input = File('${root.path}${Platform.pathSeparator}long.wav');
      await input.writeAsBytes([1, 2, 3]);
      final delegate = _ThrowingService(TranscriptionFailureKind.environment);
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(seconds: 3),
        overlap: const Duration(seconds: 1),
        maxAttempts: 3,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.transcribe(
          _request(
            input: input.path,
            output: root.path,
            config: _whisperConfig(
              modelPath: 'unused.bin',
              ffmpegExecutable: fakeFfmpeg,
            ),
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.environment,
          ),
        ),
      );
      expect(delegate.calls, 1);
    },
    skip: Platform.isWindows,
  );

  test(
    'chunking preserves input kind after normal retry budget is exhausted',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-chunk-input-',
      );
      addTearDown(() => root.delete(recursive: true));
      final fakeFfmpeg = await _fakeFfmpeg(root);
      final input = File('${root.path}${Platform.pathSeparator}long.wav');
      await input.writeAsBytes([1, 2, 3]);
      final delegate = _ThrowingService(TranscriptionFailureKind.input);
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(seconds: 3),
        overlap: const Duration(seconds: 1),
        maxAttempts: 3,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.transcribe(
          _request(
            input: input.path,
            output: root.path,
            config: _whisperConfig(
              modelPath: 'unused.bin',
              ffmpegExecutable: fakeFfmpeg,
            ),
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.input,
          ),
        ),
      );
      expect(delegate.calls, 3);
    },
    skip: Platform.isWindows,
  );

  test(
    'chunking immediately propagates cancelled failures without retrying',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lyricforge-chunk-cancelled-',
      );
      addTearDown(() => root.delete(recursive: true));
      final fakeFfmpeg = await _fakeFfmpeg(root);
      final input = File('${root.path}${Platform.pathSeparator}long.wav');
      await input.writeAsBytes([1, 2, 3]);
      final delegate = _ThrowingService(TranscriptionFailureKind.cancelled);
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(seconds: 3),
        overlap: const Duration(seconds: 1),
        maxAttempts: 3,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.transcribe(
          _request(
            input: input.path,
            output: root.path,
            config: _whisperConfig(
              modelPath: 'unused.bin',
              ffmpegExecutable: fakeFfmpeg,
            ),
          ),
        ),
        throwsA(
          isA<TranscriptionException>()
              .having(
                (error) => error.kind,
                'kind',
                TranscriptionFailureKind.cancelled,
              )
              .having((error) => error.isCancelled, 'isCancelled', isTrue),
        ),
      );
      expect(delegate.calls, 1);
    },
    skip: Platform.isWindows,
  );

  test(
    'isCancelled depends strictly on TranscriptionFailureKind.cancelled',
    () {
      const cancelled = TranscriptionException.cancelled('user aborted');
      const deceptiveUnknown = TranscriptionException('歌词识别已取消');
      const environment = TranscriptionException.environment('missing model');
      const input = TranscriptionException.input('corrupt wav');
      const busy = TranscriptionException.busy('already running');

      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.blocksQueue, isFalse);
      expect(deceptiveUnknown.kind, TranscriptionFailureKind.unknown);
      expect(deceptiveUnknown.isCancelled, isFalse);
      expect(environment.isCancelled, isFalse);
      expect(input.isCancelled, isFalse);
      expect(busy.isCancelled, isFalse);
    },
  );

  test(
    'production ASR pipeline does not branch on cancellation message text',
    () async {
      final legacyCopyControlFlow = RegExp(
        r"(?:==|!=|\.contains\s*\(|\.startsWith\s*\(|\.endsWith\s*\()\s*"
        r"'歌词识别已取消'|'歌词识别已取消'\s*(?:==|!=)",
      );
      final libRoot = Directory('lib');
      final violations = <String>[];
      var displayCopyCount = 0;

      await for (final entity in libRoot.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = await entity.readAsLines();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index].trim();
          if (line.startsWith('//')) continue;
          if (line.contains("'歌词识别已取消'")) {
            displayCopyCount += 1;
          }
          if (legacyCopyControlFlow.hasMatch(line)) {
            violations.add('${entity.path}:${index + 1}: $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Cancellation control flow must use TranscriptionFailureKind.cancelled '
            'instead of comparing against legacy message literals.',
      );
      expect(
        displayCopyCount,
        greaterThan(0),
        reason: 'User-facing cancellation copy must remain intact.',
      );

      final errorMessagePredicate = RegExp(
        r'error\.message\s*(?:==|!=|\.contains\s*\(|\.startsWith\s*\(|\.endsWith\s*\()',
      );
      const asrPipelineFiles = <String>[
        'lib/features/transcription/data/services/'
            'high_quality_transcription_service.dart',
        'lib/features/transcription/data/services/'
            'resumable_chunked_transcription_service.dart',
        'lib/features/transcription/data/services/'
            'local_project_transcription_workflow.dart',
        'lib/features/transcription/data/services/'
            'whisper_cpp_transcription_service.dart',
        'lib/features/transcription/data/services/'
            'qwen3_asr_native_transcription_service.dart',
        'lib/features/transcription/data/services/'
            'file_batch_transcription_queue.dart',
      ];
      final pipelineViolations = <String>[];
      for (final path in asrPipelineFiles) {
        final lines = await File(path).readAsLines();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index].trim();
          if (line.startsWith('//')) continue;
          if (errorMessagePredicate.hasMatch(line)) {
            pipelineViolations.add('$path:${index + 1}: $line');
          }
        }
      }

      expect(
        pipelineViolations,
        isEmpty,
        reason:
            'ASR pipeline services must not inspect error.message for control flow.',
      );

      final hqSource = await File(
        'lib/features/transcription/data/services/'
        'high_quality_transcription_service.dart',
      ).readAsString();
      expect(hqSource, contains("TranscriptionException.cancelled('歌词识别已取消')"));
      expect(hqSource, isNot(contains("TranscriptionException('歌词识别已取消')")));
    },
  );
}

TranscriptionRequest _request({
  required String input,
  required String output,
  required TranscriptionConfig config,
}) {
  return TranscriptionRequest(
    inputAudioPath: input,
    outputDirectory: output,
    config: config,
  );
}

TranscriptionConfig _whisperConfig({
  required String modelPath,
  String whisperExecutable = 'whisper-cli',
  String ffmpegExecutable = 'ffmpeg',
}) {
  return TranscriptionConfig(
    mode: TranscriptionMode.whisperOnly,
    whisperExecutable: whisperExecutable,
    modelPath: modelPath,
    ffmpegExecutable: ffmpegExecutable,
  );
}

TranscriptionConfig _qwenConfig({required String qwenExecutable}) {
  return TranscriptionConfig(
    mode: TranscriptionMode.highestQuality,
    profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
    qwenExecutable: qwenExecutable,
    qwenModelPath: 'Qwen/Qwen3-ASR-1.7B',
    qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
    whisperExecutable: 'whisper-cli',
    modelPath: 'ggml-large-v3.bin',
  );
}

Future<String> _fakeFfmpeg(Directory root) async {
  final script = File('${root.path}${Platform.pathSeparator}fake_ffmpeg.sh');
  await script.writeAsString(
    r'''#!/bin/sh
last=""
for arg in "$@"; do
  last="$arg"
done
case " $* " in
  *" -f null "*)
    echo "Duration: 00:00:10.00" >&2
    exit 0
    ;;
  *)
    dd if=/dev/zero of="$last" bs=128 count=1 2>/dev/null
    exit 0
    ;;
esac
'''
        .replaceAll(r'\"', '"'),
  );
  final chmod = await Process.run('chmod', ['+x', script.path]);
  if (chmod.exitCode != 0) {
    throw StateError('chmod failed: ${chmod.stderr}');
  }
  return script.path;
}

class _ThrowingService implements TranscriptionService {
  final TranscriptionFailureKind kind;
  final StreamController<TranscriptionProgress> _progress =
      StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  _ThrowingService(this.kind);

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls += 1;
    throw TranscriptionException(switch (kind) {
      TranscriptionFailureKind.environment => 'runtime unavailable',
      TranscriptionFailureKind.cancelled => 'cancelled by test',
      _ => 'chunk cannot be recognized',
    }, kind: kind);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _progress.close();
  }
}
