import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/forced_alignment_eval.dart';

void main() {
  test('reports boundary MAE, median, p95 and tolerance rate', () {
    final report = evaluateForcedAlignmentCorpus(jsonEncode({
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
    }));
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
    final report = evaluateForcedAlignmentCorpus(jsonEncode({
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
    }));
    final result = (report['samples']! as List).single as Map<String, dynamic>;
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
    final report = evaluateForcedAlignmentCorpus(jsonEncode({
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
    }));
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
    final report = evaluateForcedAlignmentCorpus(jsonEncode({
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
    }));
    final result = (report['samples']! as List).single as Map<String, dynamic>;
    expect(result['textRecall'], 0);
    expect(result['unmatchedExpectedSpans'], 1);
    expect(result['meanAbsoluteBoundaryErrorMs'], isNull);
    expect(result['withinToleranceBoundaryRate'], isNull);
    },
  );

  test('aggregates samples by language and validates schema', () {
    final report = evaluateForcedAlignmentCorpus(jsonEncode({
      'schemaVersion': 1,
      'samples': [
        {
          'id': 'en',
          'language': 'English',
          'referenceSpans': [{'text': 'hello', 'startMs': 0, 'endMs': 100}],
          'actualSpans': [{'text': 'hello', 'startMs': 0, 'endMs': 100}],
        },
        {
          'id': 'zh',
          'language': 'Chinese',
          'referenceSpans': [{'text': '你好', 'startMs': 200, 'endMs': 400}],
          'actualSpans': [{'text': '你好', 'startMs': 210, 'endMs': 390}],
        },
      ],
    }));
    expect(report['sampleCount'], 2);
    final langs = report['byLanguage']! as Map<String, dynamic>;
    expect(langs.keys, containsAll(['English', 'Chinese']));
    expect(
      () => evaluateForcedAlignmentCorpus('{"schemaVersion":2,"samples":[]}'),
      throwsFormatException,
    );
    expect(
      () => evaluateForcedAlignmentCorpus('{"schemaVersion":1,"samples":[]}'),
      throwsFormatException,
    );
  });

  test('rejects unordered and out-of-audio spans', () {
    expect(
      () => evaluateForcedAlignmentCorpus(jsonEncode({
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
      })),
      throwsFormatException,
    );
    expect(
      () => evaluateForcedAlignmentCorpus(jsonEncode({
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
      })),
      throwsFormatException,
    );
  });

  test(
    'captures local alignment spans as millisecond corpus entries',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? receivedPayload;
      final subscription = server.listen((request) async {
        receivedPayload = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'results': [
            {
              'items': [
                {'text': 'hello', 'start_time': 0.101, 'end_time': 0.2795},
              ],
            },
          ],
        }));
        await request.response.close();
      });
      try {
        final sample = await captureForcedAlignmentSample(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/align'),
          audioPath: 'song.wav',
          lyricText: 'hello world',
          language: 'English',
          sampleId: 'en-01',
          referenceSpansJson: jsonEncode([
            {'text': 'hello', 'startMs': 100, 'endMs': 300},
          ]),
          audioDurationMs: 2000,
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
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test('rejects remote capture endpoints before sending lyric data', () async {
    await expectLater(
      captureForcedAlignmentSample(
        endpoint: Uri.parse('https://example.com/v1/align'),
        audioPath: 'song.wav',
        lyricText: 'private lyric',
        language: 'English',
        sampleId: 'en-remote',
        referenceSpansJson: jsonEncode([
          {'text': 'lyric', 'startMs': 100, 'endMs': 200},
        ]),
        audioDurationMs: 1000,
      ),
      throwsArgumentError,
    );
  });

  test(
    'rejects captured spans that exceed the annotated audio duration',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'items': [
            {'text': 'too late', 'start_time': 1.8, 'end_time': 2.1},
          ],
        }));
        await request.response.close();
      });
      try {
        await expectLater(
          captureForcedAlignmentSample(
            endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/align'),
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
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'does not follow redirects away from the local alignment endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'https://example.com/v1/align',
        );
        await request.response.close();
      });
      try {
        await expectLater(
          captureForcedAlignmentSample(
            endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/align'),
            audioPath: 'song.wav',
            lyricText: 'private lyric',
            language: 'English',
            sampleId: 'en-redirect',
            referenceSpansJson: jsonEncode([
              {'text': 'lyric', 'startMs': 100, 'endMs': 200},
            ]),
            audioDurationMs: 1000,
          ),
          throwsFormatException,
        );
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

}
