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

    test(
      'uses the same PCM output options when extracting long-audio chunks',
      () {
        final fullAudio = AsrAudioNormalization.ffmpegArguments(
          inputPath: '/music/song.flac',
          outputPath: '/work/full.wav',
        );
        final chunk = AsrAudioNormalization.chunkArguments(
          inputPath: '/music/song.flac',
          outputPath: '/work/chunk.wav',
          start: const Duration(seconds: 8),
          duration: const Duration(minutes: 3),
        );

        expect(chunk, [
          '-y',
          '-ss',
          '8.000',
          '-i',
          '/music/song.flac',
          '-t',
          '180.000',
          '-vn',
          '-ar',
          '16000',
          '-ac',
          '1',
          '-c:a',
          'pcm_s16le',
          '/work/chunk.wav',
        ]);
        final fullAudioOutputIndex = fullAudio.indexOf('-vn');
        final chunkOutputIndex = chunk.indexOf('-vn');
        expect(
          fullAudio.sublist(fullAudioOutputIndex, fullAudio.length - 1),
          chunk.sublist(chunkOutputIndex, chunk.length - 1),
        );
      },
    );

    test('formats subsecond chunk boundaries to millisecond precision', () {
      final arguments = AsrAudioNormalization.chunkArguments(
        inputPath: '/music/song.flac',
        outputPath: '/work/chunk.wav',
        start: const Duration(milliseconds: 12345),
        duration: const Duration(milliseconds: 875),
      );

      expect(arguments[2], '12.345');
      expect(arguments[6], '0.875');
    });

    test('exposes one canonical target format', () {
      expect(AsrAudioNormalization.sampleRateHz, 16000);
      expect(AsrAudioNormalization.channelCount, 1);
      expect(AsrAudioNormalization.sampleFormat, 'pcm_s16le');
    });
  });
}
