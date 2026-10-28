import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/forced_alignment_http_client.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;
  late ForcedAlignmentHttpClient client;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}/v1/align');
    client = ForcedAlignmentHttpClient(endpoint: endpoint);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  test(
    'sends audio, arbitrary text and language to the explicit align URI',
    () async {
      final received = server.first;
      final responseFuture = received.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/align');
        expect(request.headers.contentType?.mimeType, 'application/json');
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(payload['audio'], r'C:\songs\song.wav');
        expect(payload['text'], 'confirmed lyric text');
        expect(payload['language'], 'English');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'results': [
                {
                  'items': [
                    {'text': 'confirmed', 'start_time': 0.25, 'end_time': 0.8},
                    {'text': 'lyric', 'start_time': 0.81, 'end_time': 1.1},
                    {'text': 'text', 'start_time': 1.12, 'end_time': 1.4},
                  ],
                },
              ],
            }),
          );
        await request.response.close();
      });

      final spans = await client.align(
        audioPath: r'C:\songs\song.wav',
        text: 'confirmed lyric text',
        language: 'English',
        audioDuration: const Duration(seconds: 2),
      );
      await responseFuture;

      expect(spans, hasLength(3));
      expect(spans.first.start, const Duration(milliseconds: 250));
      expect(spans.last.end, const Duration(milliseconds: 1400));
      expect(() => spans.add(spans.first), throwsUnsupportedError);
    },
  );

  test(
    'rejects non-monotonic spans instead of returning unsafe timestamps',
    () async {
      final responseFuture = server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'items': [
                {'text': 'first', 'start_time': 1.0, 'end_time': 1.2},
                {'text': 'second', 'start_time': 0.8, 'end_time': 1.1},
              ],
            }),
          );
        await request.response.close();
      });

      await expectLater(
        client.align(
          audioPath: '/tmp/song.wav',
          text: 'first second',
          language: 'English',
          audioDuration: const Duration(seconds: 3),
        ),
        throwsA(isA<ForcedAlignmentException>()),
      );
      await responseFuture;
    },
  );

  test('rejects invalid, empty and out-of-audio timestamps', () async {
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'items': [
              {'text': 'late', 'start_time': 1.0, 'end_time': 3.5},
            ],
          }),
        );
      await request.response.close();
    });

    await expectLater(
      client.align(
        audioPath: '/tmp/song.wav',
        text: 'late',
        language: 'English',
        audioDuration: const Duration(seconds: 3),
      ),
      throwsA(isA<ForcedAlignmentException>()),
    );
    await responseFuture;
  });

  test('does not treat non-success responses as aligned results', () async {
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found');
      await request.response.close();
    });

    await expectLater(
      client.align(
        audioPath: '/tmp/song.wav',
        text: 'lyric',
        language: 'English',
        audioDuration: const Duration(seconds: 3),
      ),
      throwsA(isA<ForcedAlignmentException>()),
    );
    await responseFuture;
  });

  test('enforces one deadline across response headers and body', () async {
    client.close(force: true);
    client = ForcedAlignmentHttpClient(
      endpoint: endpoint,
      requestTimeout: const Duration(milliseconds: 500),
    );
    final responseStarted = Completer<void>();
    final received = server.first;
    final responseFuture = received.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"items":');
      await request.response.flush();
      if (!responseStarted.isCompleted) responseStarted.complete();
    });

    final pending = client.align(
      audioPath: '/tmp/song.wav',
      text: 'lyric',
      language: 'English',
      audioDuration: const Duration(seconds: 3),
    );
    await responseStarted.future.timeout(const Duration(seconds: 2));
    await expectLater(
      pending,
      throwsA(
        isA<ForcedAlignmentException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
    await responseFuture;
  });

  test('force close aborts an active alignment response', () async {
    client.close(force: true);
    client = ForcedAlignmentHttpClient(
      endpoint: endpoint,
      requestTimeout: const Duration(minutes: 1),
    );
    final responseStarted = Completer<void>();
    final received = server.first;
    final responseFuture = received.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"items":');
      await request.response.flush();
      if (!responseStarted.isCompleted) responseStarted.complete();
    });

    final pending = client.align(
      audioPath: '/tmp/song.wav',
      text: 'lyric',
      language: 'English',
      audioDuration: const Duration(seconds: 3),
    );
    await responseStarted.future.timeout(const Duration(seconds: 2));
    client.close(force: true);
    await expectLater(
      pending,
      throwsA(
        isA<ForcedAlignmentException>().having(
          (error) => error.message,
          'message',
          contains('interrupted'),
        ),
      ),
    );
    await responseFuture;
  });

  test('rejects blank input before making a request', () async {
    await expectLater(
      client.align(
        audioPath: '/tmp/song.wav',
        text: ' ',
        language: 'English',
        audioDuration: const Duration(seconds: 3),
      ),
      throwsArgumentError,
    );
  });
}
