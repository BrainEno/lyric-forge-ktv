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

  test('repairs words the aligner could not place instead of failing', () async {
    // The shape the Qwen3 aligner returns for an unplaced chant: zero-length
    // words piled on one instant before a stretched word.
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'items': [
              {'text': 'whoa', 'start_time': 1.0, 'end_time': 1.0},
              {'text': 'whoa', 'start_time': 1.0, 'end_time': 1.0},
              {'text': 'fire', 'start_time': 1.0, 'end_time': 2.5},
              {'text': 'end', 'start_time': 2.5, 'end_time': 2.8},
            ],
          }),
        );
      await request.response.close();
    });

    final spans = await client.align(
      audioPath: '/tmp/song.wav',
      text: 'whoa whoa fire end',
      language: 'English',
      audioDuration: const Duration(seconds: 3),
    );
    await responseFuture;

    expect(spans.map((span) => span.text), ['whoa', 'whoa', 'fire', 'end']);
    var previousEnd = Duration.zero;
    for (final span in spans) {
      expect(span.end, greaterThan(span.start));
      expect(span.start, greaterThanOrEqualTo(previousEnd));
      previousEnd = span.end;
    }
    expect(spans.first.start, const Duration(seconds: 1));
    expect(spans[2].end, const Duration(milliseconds: 2500));
  });

  test('still rejects an end before its start', () async {
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'items': [
              {'text': 'back', 'start_time': 1.0, 'end_time': 0.5},
            ],
          }),
        );
      await request.response.close();
    });

    await expectLater(
      client.align(
        audioPath: '/tmp/song.wav',
        text: 'back',
        language: 'English',
        audioDuration: const Duration(seconds: 3),
      ),
      throwsA(isA<ForcedAlignmentException>()),
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

  group('authenticated runtime sessions', () {
    late _RecordingAuthenticator authenticator;
    late ForcedAlignmentHttpClient signedClient;

    setUp(() {
      authenticator = _RecordingAuthenticator();
      signedClient = ForcedAlignmentHttpClient(
        endpoint: endpoint,
        authenticator: authenticator,
      );
    });

    tearDown(() => signedClient.close(force: true));

    Future<List<int>> serveOnce({
      required int statusCode,
      required Object body,
    }) async {
      final request = await server.first;
      final received = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      expect(request.headers.value('x-test-signature'), 'signed');
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
      return received;
    }

    Future<List<ForcedAlignedSpanView>> align() async {
      final spans = await signedClient.align(
        audioPath: '/tmp/song.wav',
        text: 'hello world',
        language: 'English',
        audioDuration: const Duration(seconds: 2),
      );
      return spans.map((span) => (span.text, span.start)).toList();
    }

    test(
      'signs the exact request bytes and accepts proven responses',
      () async {
        final served = serveOnce(
          statusCode: HttpStatus.ok,
          body: {
            'items': [
              {'text': 'hello', 'start_time': 0.1, 'end_time': 0.5},
            ],
          },
        );

        final spans = await align();
        final sentBytes = await served;

        expect(spans.single.$1, 'hello');
        expect(authenticator.method, 'POST');
        expect(authenticator.uri, endpoint);
        expect(authenticator.body, sentBytes);
        expect(authenticator.checkedStatus, HttpStatus.ok);
        expect(utf8.decode(authenticator.checkedBody!), contains('hello'));
      },
    );

    test('discards an unproven body before decoding it', () async {
      authenticator.accept = false;
      final served = serveOnce(
        statusCode: HttpStatus.ok,
        body: {
          'items': [
            {'text': 'forged', 'start_time': 0.1, 'end_time': 0.5},
          ],
        },
      );

      await expectLater(
        align(),
        throwsA(isA<ForcedAlignmentAuthenticationException>()),
      );
      await served;
    });

    test(
      'an unproven error response is still an authentication failure',
      () async {
        authenticator.accept = false;
        final served = serveOnce(
          statusCode: HttpStatus.unauthorized,
          body: {
            'error': {'message': 'unauthorized'},
          },
        );

        await expectLater(
          align(),
          throwsA(isA<ForcedAlignmentAuthenticationException>()),
        );
        await served;
      },
    );

    test('authorization failures abort before any byte is sent', () async {
      authenticator.throwOnAuthorize = true;
      var connections = 0;
      final subscription = server.listen((request) {
        connections++;
        request.response.close();
      });

      await expectLater(align(), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      expect(authenticator.body, isNull);
      expect(connections, 0);
    });
  });
}

typedef ForcedAlignedSpanView = (String, Duration);

class _RecordingAuthenticator implements ForcedAlignmentRequestAuthenticator {
  bool accept = true;
  bool throwOnAuthorize = false;
  String? method;
  Uri? uri;
  List<int>? body;
  int? checkedStatus;
  List<int>? checkedBody;

  @override
  ForcedAlignmentRequestAuthorization authorize(
    String method,
    Uri uri,
    List<int> body,
  ) {
    if (throwOnAuthorize) {
      throw StateError('session closed');
    }
    this.method = method;
    this.uri = uri;
    this.body = List<int>.of(body);
    return _RecordingAuthorization(this);
  }
}

class _RecordingAuthorization implements ForcedAlignmentRequestAuthorization {
  _RecordingAuthorization(this._owner);

  final _RecordingAuthenticator _owner;

  @override
  Map<String, String> get headers => const {'x-test-signature': 'signed'};

  @override
  bool acceptsResponse({
    required int statusCode,
    required HttpHeaders headers,
    required List<int> body,
  }) {
    _owner.checkedStatus = statusCode;
    _owner.checkedBody = List<int>.of(body);
    return _owner.accept;
  }
}
