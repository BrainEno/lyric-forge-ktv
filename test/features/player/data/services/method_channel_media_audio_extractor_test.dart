import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/method_channel_media_audio_extractor.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_audio_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/media_audio');
  const extractor = MethodChannelMediaAudioExtractor(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the channel name matches the native side', () {
    expect(
      MethodChannelMediaAudioExtractor.channelName,
      'io.github.braineno.lyricforge/media_audio',
    );
  });

  test('sends input and output, reads path and duration', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'path': '/out/a.m4a', 'durationMs': 61500};
    });

    final result = await extractor.extractAudio(
      inputPath: '/in/a.mov',
      outputPath: '/out/a.m4a',
    );

    expect(calls.single.method, 'extractAudio');
    expect(calls.single.arguments, {
      'input': '/in/a.mov',
      'output': '/out/a.m4a',
    });
    expect(result.path, '/out/a.m4a');
    expect(result.duration, const Duration(milliseconds: 61500));
  });

  test('native error codes become user messages', () async {
    for (final (code, expected) in [
      ('no-audio', MediaAudioExtractionException.noAudio),
      ('unsupported-codec', MediaAudioExtractionException.unsupportedCodec),
      ('weird', MediaAudioExtractionException.failed),
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: code, message: 'detail');
      });
      await expectLater(
        extractor.extractAudio(inputPath: 'a', outputPath: 'b'),
        throwsA(
          isA<MediaAudioExtractionException>().having(
            (error) => error.code,
            'code',
            expected,
          ),
        ),
      );
    }
  });

  test('a platform without the channel cannot extract', () async {
    await expectLater(
      extractor.extractAudio(inputPath: 'a', outputPath: 'b'),
      throwsA(
        isA<MediaAudioExtractionException>()
            .having(
              (error) => error.code,
              'code',
              MediaAudioExtractionException.unsupportedPlatform,
            )
            .having(
              (error) => error.userMessage,
              'userMessage',
              '这台设备暂不支持从视频提取声音',
            ),
      ),
    );
  });
}
