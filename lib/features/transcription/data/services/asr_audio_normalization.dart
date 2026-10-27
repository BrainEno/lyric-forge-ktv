/// Canonical FFmpeg arguments for the audio supplied to local ASR engines.
///
/// Keep this shared by Qwen and Whisper so their input normalization cannot
/// silently drift when either adapter is changed.
class AsrAudioNormalization {
  AsrAudioNormalization._();

  static const int sampleRateHz = 16000;
  static const int channelCount = 1;
  static const String sampleFormat = 'pcm_s16le';

  static List<String> ffmpegArguments({
    required String inputPath,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ar',
      sampleRateHz.toString(),
      '-ac',
      channelCount.toString(),
      '-c:a',
      sampleFormat,
      outputPath,
    ];
  }
}
