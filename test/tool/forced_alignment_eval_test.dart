import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/qwen_native_runtime_session.dart';

import '../../tool/forced_alignment_eval.dart' as evaluator;

const _sessionTokenEnvironment = 'LYRICFORGE_QWEN_SESSION_TOKEN';

void main() {
  late _TestIdentity identity;

  setUpAll(() async {
    identity = await _TestIdentity.load();
  });

  test('reports boundary MAE, median, p95 and tolerance rate', () {
    final report = evaluator.evaluateForcedAlignmentCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'toleranceMs': 10,
        'samples': [
          {
            'id': 'en-01',
            'language': 'English',
            'audioDurationMs': 1000,
            'referenceSpans': [
              {'text': 'hello', 'startMs': 100, 'endMs': 200},
              {'text': 'world', 'startMs': 220, 'endMs': 350},
            ],
            'actualSpans': [
              {'text': 'hello', 'startMs': 110, 'endMs': 190},
              {'text': 'world', 'startMs': 240, 'endMs': 360},
            ],
          },
        ],
      }),
    );
    final result = (report['samples']! as List).single as Map<String, dynamic>;
    expect(result['textRecall'], 1);
    expect(result['textPrecision'], 1);
    expect(result['meanAbsoluteBoundaryErrorMs'], 12.5);
    expect(result['medianAbsoluteBoundaryErrorMs'], 10);
    expect(result['p95AbsoluteBoundaryErrorMs'], 20);
    expect(result['withinToleranceBoundaryCount'], 3);
    expect(result['withinToleranceBoundaryRate'], 0.75);
  });

  test(
    'normalizes full-width Latin and joins equivalent Chinese/Japanese spans',
    () {
      final report = evaluator.evaluateForcedAlignmentCorpus(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'ja-01',
              'language': 'Japanese',
              'referenceSpans': [
                {'text': 'Ｈｅｌｌｏ', 'startMs': 100, 'endMs': 200},
                {'text': '世界！', 'startMs': 220, 'endMs': 300},
              ],
              'actualSpans': [
                {'text': 'hello世界', 'startMs': 120, 'endMs': 290},
              ],
            },
          ],
        }),
      );
      final result =
          (report['samples']! as List).single as Map<String, dynamic>;
      expect(result['matchedGroups'], 1);
      expect(result['matchedExpectedSpans'], 2);
      expect(result['matchedActualSpans'], 1);
      expect(result['unmatchedExpectedSpans'], 0);
      expect(result['textRecall'], 1);
      expect(result['textPrecision'], 1);
      final groups = result['matchedGroupDetails'] as List;
      expect((groups.single as Map)['normalizedText'], 'hello世界');
    },
  );

  test('reports extra ad-lib spans without losing later repeated words', () {
    final report = evaluator.evaluateForcedAlignmentCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'en-adlib',
            'language': 'English',
            'referenceSpans': [
              {'text': 'oh', 'startMs': 100, 'endMs': 200},
              {'text': 'yeah', 'startMs': 220, 'endMs': 350},
              {'text': 'oh', 'startMs': 600, 'endMs': 700},
            ],
            'actualSpans': [
              {'text': 'oh', 'startMs': 100, 'endMs': 200},
              {'text': 'yeah', 'startMs': 220, 'endMs': 350},
              {'text': 'uh', 'startMs': 400, 'endMs': 480},
              {'text': 'oh', 'startMs': 600, 'endMs': 700},
            ],
          },
        ],
      }),
    );
    final result = (report['samples']! as List).single as Map<String, dynamic>;
    expect(result['matchedGroups'], 3);
    expect(result['unmatchedExpectedSpans'], 0);
    expect(result['unmatchedActualSpans'], 1);
    expect(result['textRecall'], 1);
    expect(result['textPrecision'], closeTo(0.8, 0.000001));
  });

  test(
    'empty output reports zero recall and no fabricated timing accuracy',
    () {
      final report = evaluator.evaluateForcedAlignmentCorpus(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'empty',
              'language': 'English',
              'referenceSpans': [
                {'text': 'hello', 'startMs': 100, 'endMs': 200},
              ],
              'actualSpans': <Map<String, Object>>[],
            },
          ],
        }),
      );
      final result =
          (report['samples']! as List).single as Map<String, dynamic>;
      expect(result['textRecall'], 0);
      expect(result['unmatchedExpectedSpans'], 1);
      expect(result['meanAbsoluteBoundaryErrorMs'], isNull);
      expect(result['withinToleranceBoundaryRate'], isNull);
    },
  );

  test('aggregates samples by language and validates schema', () {
    final report = evaluator.evaluateForcedAlignmentCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'en',
            'language': 'English',
            'referenceSpans': [
              {'text': 'hello', 'startMs': 0, 'endMs': 100},
            ],
            'actualSpans': [
              {'text': 'hello', 'startMs': 0, 'endMs': 100},
            ],
          },
          {
            'id': 'zh',
            'language': 'Chinese',
            'referenceSpans': [
              {'text': '你好', 'startMs': 200, 'endMs': 400},
            ],
            'actualSpans': [
              {'text': '你好', 'startMs': 210, 'endMs': 390},
            ],
          },
        ],
      }),
    );
    expect(report['sampleCount'], 2);
    final langs = report['byLanguage']! as Map<String, dynamic>;
    expect(langs.keys, containsAll(['English', 'Chinese']));
    expect(
      () => evaluator.evaluateForcedAlignmentCorpus(
        '{"schemaVersion":2,"samples":[]}',
      ),
      throwsFormatException,
    );
    expect(
      () => evaluator.evaluateForcedAlignmentCorpus(
        '{"schemaVersion":1,"samples":[]}',
      ),
      throwsFormatException,
    );
  });

  test('rejects unordered and out-of-audio spans', () {
    expect(
      () => evaluator.evaluateForcedAlignmentCorpus(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'bad-order',
              'language': 'English',
              'referenceSpans': [
                {'text': 'late', 'startMs': 300, 'endMs': 400},
                {'text': 'early', 'startMs': 100, 'endMs': 200},
              ],
              'actualSpans': [],
            },
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => evaluator.evaluateForcedAlignmentCorpus(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'bad-duration',
              'language': 'English',
              'audioDurationMs': 350,
              'referenceSpans': [
                {'text': 'too long', 'startMs': 100, 'endMs': 400},
              ],
              'actualSpans': [
                {'text': 'too long', 'startMs': 100, 'endMs': 300},
              ],
            },
          ],
        }),
      ),
      throwsFormatException,
    );
  });

  test(
    'captures local alignment spans as millisecond corpus entries',
    () async {
      Map<String, dynamic>? receivedPayload;
      final runtime = await _TestRuntime.bind(identity, (request) async {
        receivedPayload =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'results': [
              {
                'items': [
                  {'text': 'hello', 'start_time': 0.101, 'end_time': 0.2795},
                ],
              },
            ],
          }),
        );
        await request.response.close();
      });
      try {
        final sample = await evaluator.captureForcedAlignmentSample(
          session: runtime.session,
          audioPath: 'song.wav',
          lyricText: 'hello world',
          language: 'English',
          sampleId: 'en-01',
          referenceSpansJson: jsonEncode([
            {'text': 'hello', 'startMs': 100, 'endMs': 300},
          ]),
          audioDurationMs: 2000,
        );
        expect(
          runtime.requests.single.authorization,
          'Bearer ${runtime.token}',
        );
        expect(receivedPayload?['audio'], 'song.wav');
        expect(receivedPayload?['text'], 'hello world');
        expect(receivedPayload?['language'], 'English');
        expect(sample['id'], 'en-01');
        expect((sample['actualSpans'] as List).single, {
          'text': 'hello',
          'startMs': 101,
          'endMs': 280,
        });
        expect((sample['referenceSpans'] as List).single, {
          'text': 'hello',
          'startMs': 100,
          'endMs': 300,
        });
      } finally {
        await runtime.close();
      }
    },
  );

  test(
    'rejects captured spans that exceed the annotated audio duration',
    () async {
      final runtime = await _TestRuntime.bind(identity, (request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [
              {'text': 'too late', 'start_time': 1.8, 'end_time': 2.1},
            ],
          }),
        );
        await request.response.close();
      });
      try {
        await expectLater(
          evaluator.captureForcedAlignmentSample(
            session: runtime.session,
            audioPath: 'song.wav',
            lyricText: 'too late',
            language: 'English',
            sampleId: 'en-overrun',
            referenceSpansJson: jsonEncode([
              {'text': 'too late', 'startMs': 1700, 'endMs': 1900},
            ]),
            audioDurationMs: 2000,
          ),
          throwsFormatException,
        );
      } finally {
        await runtime.close();
      }
    },
  );

  test(
    'does not follow redirects or forward session credentials to another process',
    () async {
      var redirectedRequests = 0;
      final target = await _TestRuntime.bind(
        identity,
        (request) async {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
        },
        onRequest: (_) => redirectedRequests++,
      );
      final source = await _TestRuntime.bind(identity, (request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            target.session.endpoint('/v1/align').toString(),
          );
        await request.response.close();
      });
      try {
        await expectLater(
          evaluator.captureForcedAlignmentSample(
            session: source.session,
            audioPath: 'song.wav',
            lyricText: 'private lyric',
            language: 'English',
            sampleId: 'en-redirect',
            referenceSpansJson: jsonEncode([
              {'text': 'lyric', 'startMs': 100, 'endMs': 200},
            ]),
            audioDurationMs: 1000,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('HTTP 302'),
            ),
          ),
        );
        expect(redirectedRequests, 0);
      } finally {
        await source.close();
        await target.close();
      }
    },
  );

  test(
    'preserves a new output file created while alignment is running',
    () async {
      final temp = await Directory.systemTemp.createTemp('alignment-capture-');
      final audio = File('${temp.path}/song.wav')..writeAsStringSync('audio');
      final lyrics = File('${temp.path}/lyrics.txt')
        ..writeAsStringSync('hello');
      final reference = File('${temp.path}/reference.json')
        ..writeAsStringSync(
          jsonEncode([
            {'text': 'hello', 'startMs': 100, 'endMs': 200},
          ]),
        );
      final output = File('${temp.path}/corpus.json');
      final runtime = await _TestRuntime.bind(identity, (request) async {
        await utf8.decoder.bind(request).join();
        await output.writeAsString('created during alignment');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [
              {'text': 'hello', 'start_time': 0.1, 'end_time': 0.2},
            ],
          }),
        );
        await request.response.close();
      });
      final readyRecord = await runtime.writeReadyRecord(temp);
      try {
        exitCode = 0;
        await evaluator.runForcedAlignmentEval([
          'capture',
          '--ready-record',
          readyRecord.path,
          '--audio',
          audio.path,
          '--text-file',
          lyrics.path,
          '--reference',
          reference.path,
          '--id',
          'en-output-race',
          '--language',
          'English',
          '--duration-ms',
          '1000',
          '--output',
          output.path,
        ], environment: runtime.environment);
        expect(exitCode, 2);
        expect(await output.readAsString(), 'created during alignment');
      } finally {
        exitCode = 0;
        await runtime.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'appends a sample while preserving corpus evaluation settings',
    () async {
      final temp = await Directory.systemTemp.createTemp('alignment-append-');
      final audio = File('${temp.path}/song.wav')..writeAsStringSync('audio');
      final lyrics = File('${temp.path}/lyrics.txt')..writeAsStringSync('new');
      final reference = File('${temp.path}/reference.json')
        ..writeAsStringSync(
          jsonEncode([
            {'text': 'new', 'startMs': 300, 'endMs': 500},
          ]),
        );
      final corpusFile = File('${temp.path}/corpus.json');
      await corpusFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'toleranceMs': 75,
          'maxGroupSpans': 4,
          'samples': [
            {
              'id': 'baseline',
              'language': 'English',
              'audioDurationMs': 1000,
              'referenceSpans': [
                {'text': 'old', 'startMs': 100, 'endMs': 200},
              ],
              'actualSpans': [
                {'text': 'old', 'startMs': 100, 'endMs': 200},
              ],
            },
          ],
        }),
      );
      final runtime = await _TestRuntime.bind(identity, (request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [
              {'text': 'new', 'start_time': 0.3, 'end_time': 0.5},
            ],
          }),
        );
        await request.response.close();
      });
      final readyRecord = await runtime.writeReadyRecord(temp);
      try {
        exitCode = 0;
        await evaluator.runForcedAlignmentEval([
          'capture',
          '--ready-record',
          readyRecord.path,
          '--audio',
          audio.path,
          '--text-file',
          lyrics.path,
          '--reference',
          reference.path,
          '--id',
          'en-appended',
          '--language',
          'English',
          '--duration-ms',
          '1000',
          '--reference-reviewed',
          '--model-revision',
          'Qwen3-ForcedAligner-0.6B@revision-test',
          '--runtime-version',
          'qwen3-asr-rs-test',
          '--append-to',
          corpusFile.path,
        ], environment: runtime.environment);
        expect(exitCode, 0);
        final corpus =
            jsonDecode(await corpusFile.readAsString()) as Map<String, dynamic>;
        expect(corpus['toleranceMs'], 75);
        expect(corpus['maxGroupSpans'], 4);
        final samples = corpus['samples'] as List<dynamic>;
        expect(samples, hasLength(2));
        expect((samples[0] as Map)['id'], 'baseline');
        expect((samples[1] as Map)['id'], 'en-appended');
        final captured = samples[1] as Map;
        expect(
          captured['audioSha256'],
          sha256.convert(utf8.encode('audio')).toString(),
        );
        expect(captured['referenceReviewed'], true);
        expect(
          captured['modelRevision'],
          'Qwen3-ForcedAligner-0.6B@revision-test',
        );
        expect(captured['runtimeVersion'], 'qwen3-asr-rs-test');
        expect(captured['actualSpans'], [
          {'text': 'new', 'startMs': 300, 'endMs': 500},
        ]);
      } finally {
        exitCode = 0;
        await runtime.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test('reports missing and complete ForcedAligner provenance', () {
    final complete = evaluator.evaluateForcedAlignmentCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'en-complete',
            'language': 'English',
            'audioSha256': List.filled(64, 'a').join(),
            'audioDurationMs': 1000,
            'referenceReviewed': true,
            'modelRevision': 'Qwen3-ForcedAligner-0.6B@revision-test',
            'runtimeVersion': 'qwen3-asr-rs-test',
            'referenceSpans': [
              {'text': 'hello', 'startMs': 100, 'endMs': 200},
            ],
            'actualSpans': [
              {'text': 'hello', 'startMs': 105, 'endMs': 205},
            ],
          },
        ],
      }),
    );
    final provenance = complete['provenance'] as Map<String, dynamic>;
    expect(provenance['warnings'], isEmpty);
    expect(provenance['samplesWithAudioFingerprint'], 1);
    final sample =
        (complete['samples']! as List).single as Map<String, dynamic>;
    expect(sample['modelRevision'], 'Qwen3-ForcedAligner-0.6B@revision-test');

    final legacy = evaluator.evaluateForcedAlignmentCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'en-legacy',
            'language': 'English',
            'referenceSpans': [
              {'text': 'hello', 'startMs': 100, 'endMs': 200},
            ],
            'actualSpans': [
              {'text': 'hello', 'startMs': 100, 'endMs': 200},
            ],
          },
        ],
      }),
    );
    final legacyProvenance = legacy['provenance'] as Map<String, dynamic>;
    expect(legacyProvenance['warnings'], isNotEmpty);
    expect(legacyProvenance['samplesMissingAudioFingerprint'], ['en-legacy']);
  });

  test(
    'strict provenance writes the report before failing incomplete corpus',
    () async {
      final temp = await Directory.systemTemp.createTemp('alignment-strict-');
      final corpus = File('${temp.path}/corpus.json');
      final report = File('${temp.path}/report.json');
      await corpus.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'legacy',
              'language': 'English',
              'referenceSpans': [
                {'text': 'hello', 'startMs': 100, 'endMs': 200},
              ],
              'actualSpans': [
                {'text': 'hello', 'startMs': 100, 'endMs': 200},
              ],
            },
          ],
        }),
      );
      try {
        exitCode = 0;
        await evaluator.runForcedAlignmentEval([
          corpus.path,
          '--require-provenance',
          '--output',
          report.path,
        ]);
        expect(exitCode, 2);
        expect(await report.exists(), isTrue);
        final decoded =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        final provenance = decoded['provenance'] as Map<String, dynamic>;
        expect(provenance['warnings'], isNotEmpty);
      } finally {
        exitCode = 0;
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'strict provenance accepts complete metadata regardless of option order',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'alignment-strict-pass-',
      );
      final corpus = File('${temp.path}/corpus.json');
      final report = File('${temp.path}/report.json');
      await corpus.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'complete',
              'language': 'English',
              'audioSha256': List.filled(64, 'b').join(),
              'audioDurationMs': 1000,
              'referenceReviewed': true,
              'modelRevision': 'Qwen3-ForcedAligner-0.6B@revision-test',
              'runtimeVersion': 'qwen3-asr-rs-test',
              'referenceSpans': [
                {'text': 'hello', 'startMs': 100, 'endMs': 200},
              ],
              'actualSpans': [
                {'text': 'hello', 'startMs': 100, 'endMs': 200},
              ],
            },
          ],
        }),
      );
      try {
        exitCode = 0;
        await evaluator.runForcedAlignmentEval([
          '--output',
          report.path,
          '--require-provenance',
          corpus.path,
        ]);
        expect(exitCode, 0);
        final decoded =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        final provenance = decoded['provenance'] as Map<String, dynamic>;
        expect(provenance['warnings'], isEmpty);
      } finally {
        exitCode = 0;
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'capture refuses to preserve provenance if audio changes in flight',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'alignment-audio-race-',
      );
      final audio = File('${temp.path}/song.wav')..writeAsStringSync('audio');
      final lyrics = File('${temp.path}/lyrics.txt')
        ..writeAsStringSync('hello');
      final reference = File('${temp.path}/reference.json')
        ..writeAsStringSync(
          jsonEncode([
            {'text': 'hello', 'startMs': 100, 'endMs': 200},
          ]),
        );
      final output = File('${temp.path}/corpus.json');
      final runtime = await _TestRuntime.bind(identity, (request) async {
        await utf8.decoder.bind(request).join();
        await audio.writeAsString('changed audio');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [
              {'text': 'hello', 'start_time': 0.1, 'end_time': 0.2},
            ],
          }),
        );
        await request.response.close();
      });
      final readyRecord = await runtime.writeReadyRecord(temp);
      try {
        exitCode = 0;
        await evaluator.runForcedAlignmentEval([
          'capture',
          '--ready-record',
          readyRecord.path,
          '--audio',
          audio.path,
          '--text-file',
          lyrics.path,
          '--reference',
          reference.path,
          '--id',
          'en-audio-race',
          '--language',
          'English',
          '--duration-ms',
          '1000',
          '--output',
          output.path,
        ], environment: runtime.environment);
        expect(exitCode, 2);
        expect(await output.exists(), isFalse);
      } finally {
        exitCode = 0;
        await runtime.close();
        await temp.delete(recursive: true);
      }
    },
  );
}


class _TestIdentity {
  final Uint8List certificateDer;
  final Uint8List certificatePem;
  final Uint8List privateKeyPem;

  const _TestIdentity({
    required this.certificateDer,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  static Future<_TestIdentity> load() async {
    const root = 'test/fixtures/qwen_runtime_test_identity';
    final certificatePem = await File('$root/certificate.pem').readAsBytes();
    final privateKeyPem = await File('$root/private_key.pem').readAsBytes();
    final encoded = utf8
        .decode(certificatePem)
        .replaceAll(
          RegExp(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s'),
          '',
        );
    return _TestIdentity(
      certificateDer: base64Decode(encoded),
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
    );
  }

  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChainBytes(certificatePem)
    ..usePrivateKeyBytes(privateKeyPem);
}

class _TestRuntime {
  final HttpServer server;
  final StreamSubscription<HttpRequest> _subscription;
  final QwenNativeRuntimeSession session;
  final String token;
  final String readinessLine;
  final List<({String method, Uri uri, String? authorization})> requests;

  _TestRuntime({
    required this.server,
    required StreamSubscription<HttpRequest> subscription,
    required this.session,
    required this.token,
    required this.readinessLine,
    required this.requests,
  }) : _subscription = subscription;

  Map<String, String> get environment => {
    _sessionTokenEnvironment: token,
  };

  static Future<_TestRuntime> bind(
    _TestIdentity identity,
    Future<void> Function(HttpRequest request) handler, {
    void Function(HttpRequest request)? onRequest,
  }) async {
    final token = createQwenRuntimeSessionToken();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.serverContext(),
    );
    final session = QwenNativeRuntimeSession(
      port: server.port,
      certificateDer: identity.certificateDer,
      token: token,
    );
    final requests = <({String method, Uri uri, String? authorization})>[];
    final subscription = server.listen((request) async {
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      requests.add((
        method: request.method,
        uri: request.uri,
        authorization: authorization,
      ));
      onRequest?.call(request);
      if (authorization != 'Bearer $token') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      await handler(request);
    });
    return _TestRuntime(
      server: server,
      subscription: subscription,
      session: session,
      token: token,
      readinessLine:
          '$qwenRuntimeReadyPrefix\t${server.port}\t'
          '${base64Encode(identity.certificateDer)}',
      requests: requests,
    );
  }

  Future<File> writeReadyRecord(Directory directory) async {
    final file = File('${directory.path}/runtime-ready.txt');
    await file.writeAsString('$readinessLine\n', flush: true);
    return file;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await server.close(force: true);
  }
}
