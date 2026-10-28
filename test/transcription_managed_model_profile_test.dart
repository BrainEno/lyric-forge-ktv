import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/native_transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  group('managed Qwen profile paths', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('lyricforge-model-test-');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('RTX profile preserves matching local managed model directories',
        () async {
      final qwen = Directory(
        '${tempRoot.path}${Platform.pathSeparator}Qwen--Qwen3-ASR-1.7B',
      );
      final aligner = Directory(
        '${tempRoot.path}${Platform.pathSeparator}Qwen--Qwen3-ForcedAligner-0.6B',
      );
      await qwen.create();
      await aligner.create();

      final resolver = NativeTranscriptionProfileResolver(
        hardwareOverride: const TranscriptionHardwareInfo(
          operatingSystem: 'windows',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
          gpuMemoryMb: 16384,
        ),
      );

      final resolved = await resolver.resolve(
        TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
          qwenModelPath: qwen.path,
          qwenAlignerModelPath: aligner.path,
          whisperExecutable: 'whisper-cli.exe',
          modelPath: 'ggml-large-v3.bin',
        ),
      );

      expect(resolved.config.qwenModelPath, qwen.path);
      expect(resolved.config.qwenAlignerModelPath, aligner.path);
    });

    test('RTX profile rejects a local model directory for the wrong model size',
        () async {
      final wrongModel = Directory(
        '${tempRoot.path}${Platform.pathSeparator}Qwen--Qwen3-ASR-0.6B',
      );
      await wrongModel.create();

      final resolver = NativeTranscriptionProfileResolver(
        hardwareOverride: const TranscriptionHardwareInfo(
          operatingSystem: 'windows',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
          gpuMemoryMb: 16384,
        ),
      );

      final resolved = await resolver.resolve(
        TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          profilePreference: TranscriptionProfilePreference.rtx5080HighQuality,
          qwenModelPath: wrongModel.path,
          whisperExecutable: 'whisper-cli.exe',
          modelPath: 'ggml-large-v3.bin',
        ),
      );

      expect(resolved.config.qwenModelPath, 'Qwen/Qwen3-ASR-1.7B');
    });
  });
}
