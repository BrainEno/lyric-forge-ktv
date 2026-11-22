import 'package:flutter/services.dart';

import '../../domain/services/media_audio_extractor.dart';

/// [MediaAudioExtractor] backed by the app's own native code: AVFoundation on
/// iOS (`ios/Runner/AppDelegate.swift`), MediaExtractor + MediaMuxer on
/// Android (`MediaAudioExtractor.kt`).
class MethodChannelMediaAudioExtractor implements MediaAudioExtractor {
  static const String channelName = 'io.github.braineno.lyricforge/media_audio';

  final MethodChannel _channel;

  const MethodChannelMediaAudioExtractor({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  @override
  Future<ExtractedAudio> extractAudio({
    required String inputPath,
    required String outputPath,
  }) async {
    final Map<Object?, Object?>? reply;
    try {
      reply = await _channel.invokeMapMethod<Object?, Object?>('extractAudio', {
        'input': inputPath,
        'output': outputPath,
      });
    } on MissingPluginException {
      throw const MediaAudioExtractionException(
        MediaAudioExtractionException.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw MediaAudioExtractionException(_codeOf(error.code), error.message);
    }
    final path = reply?['path'];
    final durationMs = reply?['durationMs'];
    return ExtractedAudio(
      path: path is String && path.isNotEmpty ? path : outputPath,
      duration: durationMs is num && durationMs > 0
          ? Duration(milliseconds: durationMs.round())
          : null,
    );
  }

  static String _codeOf(String code) => switch (code) {
    MediaAudioExtractionException.noAudio ||
    MediaAudioExtractionException.unsupportedCodec ||
    MediaAudioExtractionException.unsupportedPlatform => code,
    _ => MediaAudioExtractionException.failed,
  };
}
