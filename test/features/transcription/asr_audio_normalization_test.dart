import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_audio_normalization.dart';

void main() {
  group('AsrAudioNormalization', () {
    test('builds stable 16 kHz mono PCM arguments without shell quoting', () {
      final arguments = AsrAudioNormalization.ffmpegArguments(
        inputPath: r'D:\Music Library\recording source.m4a',
        outputPath: r'D:\LyricForge\normalized input.wav',
      );

      expect(arguments, [
        '-y',
        '-i',
        r'D:\Music Library\recording source.m4a',
        '-vn',
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        r'D:\LyricForge\normalized input.wav',
      ]);
    });

    test('keeps the same normalization contract for both engine outputs', () {
      final qwenArguments = AsrAudioNormalization.ffmpegArguments(
        inputPath: '/music/source with spaces.flac',
        outputPath: '/work/qwen input.wav',
      );
      final whisperArguments = AsrAudioNormalization.ffmpegArguments(
        inputPath: '/music/source with spaces.flac',
        outputPath: '/work/whisper input.wav',
      );

      expect(
        qwenArguments.sublist(0, qwenArguments.length - 1),
        whisperArguments.sublist(0, whisperArguments.length - 1),
      );
      expect(qwenArguments.last, '/work/qwen input.wav');
      expect(whisperArguments.last, '/work/whisper input.wav');
    });

    test('exposes one canonical target format', () {
      expect(AsrAudioNormalization.sampleRateHz, 16000);
      expect(AsrAudioNormalization.channelCount, 1);
      expect(AsrAudioNormalization.sampleFormat, 'pcm_s16le');
    });
  });
}
