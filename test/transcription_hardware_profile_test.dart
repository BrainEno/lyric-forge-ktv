import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/native_transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  group('NativeTranscriptionProfileResolver', () {
    test('selects RTX 5080 quality profile on Windows', () async {
      final resolver = NativeTranscriptionProfileResolver(
        hardwareOverride: const TranscriptionHardwareInfo(
          operatingSystem: 'windows',
          architecture: 'x86_64',
          gpuName: 'NVIDIA GeForce RTX 5080',
          gpuMemoryMb: 16384,
          systemMemoryMb: 20480,
        ),
      );

      final resolved = await resolver.resolve(
        const TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          profilePreference: TranscriptionProfilePreference.automatic,
          qwenExecutable: 'qwen3-asr.exe',
          whisperExecutable: 'whisper-cli.exe',
          modelPath: 'ggml-large-v3.bin',
        ),
      );

      expect(
        resolved.profile,
        TranscriptionProfilePreference.rtx5080HighQuality,
      );
      expect(
        resolved.config.engineOrder,
        TranscriptionEngineOrder.qwenPrimary,
      );
      expect(resolved.config.qwenModelPath, 'Qwen/Qwen3-ASR-1.7B');
      expect(resolved.config.qwenDevice, 'cuda');
      expect(resolved.config.qwenDtype, 'bf16');
    });

    test('selects Intel Mac quality profile on x86_64 macOS', () async {
      final resolver = NativeTranscriptionProfileResolver(
        hardwareOverride: const TranscriptionHardwareInfo(
          operatingSystem: 'macos',
          architecture: 'x86_64',
          cpuName: 'Intel Core i9',
          gpuName: 'AMD Radeon Pro 5700 XT',
          systemMemoryMb: 40960,
        ),
      );

      final resolved = await resolver.resolve(
        const TranscriptionConfig(
          mode: TranscriptionMode.highestQuality,
          profilePreference: TranscriptionProfilePreference.automatic,
          qwenExecutable: 'qwen3-asr',
          whisperExecutable: 'whisper-cli',
          modelPath: 'ggml-large-v3.bin',
        ),
      );

      expect(
        resolved.profile,
        TranscriptionProfilePreference.intelMacHighQuality,
      );
      expect(
        resolved.config.engineOrder,
        TranscriptionEngineOrder.whisperPrimary,
      );
      expect(resolved.config.qwenModelPath, 'Qwen/Qwen3-ASR-0.6B');
      expect(resolved.config.qwenDevice, 'cpu');
      expect(resolved.config.qwenDtype, 'f32');
    });

    test('custom profile preserves manual runtime choices', () async {
      final resolver = NativeTranscriptionProfileResolver(
        hardwareOverride: const TranscriptionHardwareInfo(
          operatingSystem: 'macos',
          architecture: 'x86_64',
        ),
      );

      const config = TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        profilePreference: TranscriptionProfilePreference.custom,
        engineOrder: TranscriptionEngineOrder.qwenPrimary,
        qwenExecutable: '/custom/qwen',
        qwenModelPath: '/custom/model',
        qwenAlignerModelPath: '/custom/aligner',
        qwenDevice: 'cpu',
        qwenDtype: 'f32',
        whisperExecutable: '/custom/whisper',
        modelPath: '/custom/whisper.bin',
      );

      final resolved = await resolver.resolve(config);

      expect(resolved.profile, TranscriptionProfilePreference.custom);
      expect(resolved.config.qwenModelPath, '/custom/model');
      expect(resolved.config.qwenDevice, 'cpu');
      expect(
        resolved.config.engineOrder,
        TranscriptionEngineOrder.qwenPrimary,
      );
    });
  });
}
