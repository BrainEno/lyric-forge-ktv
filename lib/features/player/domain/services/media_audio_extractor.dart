/// Pulls the sound track out of a video into a small audio file (D-056).
abstract class MediaAudioExtractor {
  /// Writes the first audio track of the video at [inputPath] to
  /// [outputPath] as AAC in an `.m4a` file and returns the result.
  ///
  /// Throws [MediaAudioExtractionException] when the video has no sound, its
  /// sound cannot be read, or the platform cannot extract at all.
  Future<ExtractedAudio> extractAudio({
    required String inputPath,
    required String outputPath,
  });
}

class ExtractedAudio {
  final String path;
  final Duration? duration;

  const ExtractedAudio({required this.path, this.duration});
}

/// Why extraction failed; [code] is one of the constants below.
class MediaAudioExtractionException implements Exception {
  static const String noAudio = 'no-audio';
  static const String unsupportedCodec = 'unsupported-codec';
  static const String unsupportedPlatform = 'unsupported-platform';
  static const String failed = 'export-failed';

  final String code;
  final String? detail;

  const MediaAudioExtractionException(this.code, [this.detail]);

  /// What to tell the user.
  String get userMessage => switch (code) {
    noAudio => '这个视频没有声音',
    unsupportedCodec => '这个视频的音轨格式暂不支持，可以先用其他 App 转成 MP4',
    unsupportedPlatform => '这台设备暂不支持从视频提取声音',
    _ => '提取声音失败${detail == null || detail!.isEmpty ? '' : '：$detail'}',
  };

  @override
  String toString() => 'MediaAudioExtractionException($code, $detail)';
}
