import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  group('TranscriptionConfig', () {
    test('migrates legacy Whisper-only settings without forcing Qwen', () {
      final config = TranscriptionConfig.fromJson({
        'whisperExecutable': 'whisper-cli',
        'modelPath': 'ggml-large-v3.bin',
        'ffmpegExecutable': 'ffmpeg',
        'language': 'auto',
      });

      expect(config.mode, TranscriptionMode.whisperOnly);
      expect(config.isWhisperConfigured, isTrue);
      expect(config.isConfigured, isTrue);
    });

    test('migrates legacy high quality settings to automatic profile', () {
      final config = TranscriptionConfig.fromJson({
        'mode': 'highestQuality',
        'qwenExecutable': 'qwen3-asr',
        'qwenModelPath': 'Qwen/Qwen3-ASR-1.7B',
        'qwenAlignerModelPath': 'Qwen/Qwen3-ForcedAligner-0.6B',
        'qwenDevice': 'cuda',
        'qwenDtype': 'bf16',
        'whisperExecutable': 'whisper-cli',
        'modelPath': 'ggml-large-v3.bin',
      });

      expect(
        config.profilePreference,
        TranscriptionProfilePreference.automatic,
      );
      expect(config.isConfigured, isTrue);
    });

    test('highest quality still runs when only Whisper is set up', () {
      // Whisper is the baseline. A missing second engine must not make the
      // configuration unusable: the run degrades and records why.
      const incomplete = TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        qwenExecutable: '',
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
      );

      expect(incomplete.isWhisperConfigured, isTrue);
      expect(incomplete.isQwenConfigured, isFalse);
      expect(incomplete.isHighQualityConfigured, isFalse);
      expect(incomplete.isConfigured, isTrue);
      expect(incomplete.runsDualEngine, isFalse);
      expect(incomplete.willDegradeToWhisper, isTrue);

      const complete = TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        qwenExecutable: 'qwen3-asr',
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
      );

      expect(complete.qwenModelPath, 'Qwen/Qwen3-ASR-1.7B');
      expect(complete.qwenAlignerModelPath, 'Qwen/Qwen3-ForcedAligner-0.6B');
      expect(complete.isHighQualityConfigured, isTrue);
      expect(complete.isConfigured, isTrue);
      expect(complete.runsDualEngine, isTrue);
      expect(complete.willDegradeToWhisper, isFalse);
    });

    test('a configuration without Whisper cannot recognise anything', () {
      const noWhisper = TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        qwenExecutable: 'qwen3-asr',
        whisperExecutable: '',
        modelPath: '',
      );

      // The optional engine alone is not a usable baseline: there would be
      // nothing to fall back to.
      expect(noWhisper.isQwenConfigured, isTrue);
      expect(noWhisper.isConfigured, isFalse);
    });

    test('round trips high quality fallback policy', () {
      const original = TranscriptionConfig(
        mode: TranscriptionMode.highestQuality,
        qwenExecutable: 'qwen3-asr.exe',
        qwenModelPath: 'Qwen/Qwen3-ASR-1.7B',
        qwenAlignerModelPath: 'Qwen/Qwen3-ForcedAligner-0.6B',
        qwenDevice: 'cuda',
        qwenDtype: 'bf16',
        whisperExecutable: 'whisper-cli.exe',
        modelPath: 'ggml-large-v3.bin',
        ffmpegExecutable: 'ffmpeg.exe',
        language: 'ja',
        fallbackConfidenceThreshold: 80,
        maxFallbackSegments: 20,
      );

      final restored = TranscriptionConfig.fromJson(original.toJson());

      expect(restored.mode, TranscriptionMode.highestQuality);
      expect(restored.qwenDevice, 'cuda');
      expect(restored.qwenDtype, 'bf16');
      expect(restored.language, 'ja');
      expect(restored.fallbackConfidenceThreshold, 80);
      expect(restored.maxFallbackSegments, 20);
      expect(restored.downloadProxy, '');
      expect(restored.isConfigured, isTrue);
    });

    test('persists an optional model download proxy', () {
      const original = TranscriptionConfig(
        whisperExecutable: 'whisper-cli',
        modelPath: 'ggml-large-v3.bin',
        downloadProxy: 'http://127.0.0.1:7890',
      );

      final restored = TranscriptionConfig.fromJson(original.toJson());

      expect(restored.downloadProxy, 'http://127.0.0.1:7890');
    });
  });
}
