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
    final root = await Directory.systemTemp.createTemp('lyricforge-whisper-input-');
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

  test('Whisper treats missing managed model and executable as environment',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-whisper-env-');
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
  });

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
      final root = await Directory.systemTemp.createTemp('lyricforge-chunk-env-');
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

  test('chunking preserves input kind after normal retry budget is exhausted',
      () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-chunk-input-');
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
  }, skip: Platform.isWindows);
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
  await script.writeAsString(r'''#!/bin/sh
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
    : > "$last"
    exit 0
    ;;
esac
'''.replaceAll(r'\"', '"'));
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
    throw TranscriptionException(
      kind == TranscriptionFailureKind.environment
          ? 'runtime unavailable'
          : 'chunk cannot be recognized',
      kind: kind,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _progress.close();
  }
}
