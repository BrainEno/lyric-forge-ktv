import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/forced_alignment_http_client.dart';

void main() {
  late HttpServer server;
  late ForcedAlignmentHttpClient client;
  late ForcedAlignmentProofreadService service;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ForcedAlignmentHttpClient(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/align'),
    );
    service = ForcedAlignmentProofreadService(runner: client.align);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  const duration = Duration(seconds: 3);
  final draft = LyricDocument(
    language: 'English',
    lines: [
      LyricLine(
        id: 'line-1',
        text: 'hello world',
        startTime: const Duration(milliseconds: 100),
        endTime: const Duration(milliseconds: 1500),
        confidence: 42,
      ),
    ],
  );

  test('adds validated aligner spans as review evidence without editing lyrics', () async {
    final responseFuture = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/align');
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(payload['text'], 'hello world');
      expect(payload['language'], 'English');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'results': [
            {
              'items': [
                {'text': 'hello', 'start_time': 0.2, 'end_time': 0.6},
                {'text': 'world', 'start_time': 0.7, 'end_time': 1.1},
              ],
            },
          ],
        }));
      await request.response.close();
    });

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );
    await responseFuture;

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.warning, isNull);
    expect(outcome.result.lines.single.tokens, hasLength(2));
    expect(
      outcome.result.lines.single.tokens.every(
        (token) => token.source == ProofreadTimeSource.forcedAligner,
      ),
      isTrue,
    );
    expect(outcome.result.proposedDocument.lines.single.text, 'hello world');
    expect(
      outcome.result.proposedDocument.lines.single.startTime,
      const Duration(milliseconds: 100),
    );
    expect(
      outcome.result.proposedDocument.lines.single.endTime,
      const Duration(milliseconds: 1500),
    );
    expect(draft.lines.single.confidence, 42);
  });

  test('warns when returned spans do not cover every lyric line', () async {
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'items': [
            {'text': 'unrelated', 'start_time': 0.2, 'end_time': 0.6},
          ],
        }));
      await request.response.close();
    });

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );
    await responseFuture;

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.warning, contains('matched 0 of 1'));
    expect(outcome.warning, contains('Unmatched lyric lines: 1'));
    expect(outcome.result.alignmentDiagnostics!.unmatchedLineNumbers, [1]);
    expect(outcome.result.lines.single.tokens, isEmpty);
    expect(outcome.result.proposedDocument.lines.single.text, 'hello world');
  });

  test('reports skipped spans even when every lyric line matches', () async {
    final twoLineDraft = LyricDocument(
      language: 'English',
      lines: [
        LyricLine(
          id: 'hello',
          text: 'hello',
          startTime: const Duration(milliseconds: 100),
          endTime: const Duration(milliseconds: 1000),
          confidence: 80,
        ),
        LyricLine(
          id: 'world',
          text: 'world',
          startTime: const Duration(milliseconds: 1200),
          endTime: const Duration(milliseconds: 2200),
          confidence: 80,
        ),
      ],
    );
    service = ForcedAlignmentProofreadService(
      runner: ({
        required String audioPath,
        required String text,
        required String language,
        required Duration audioDuration,
      }) async => [
        ForcedAlignedSpan(
          text: 'hello',
          start: const Duration(milliseconds: 200),
          end: const Duration(milliseconds: 400),
        ),
        ForcedAlignedSpan(
          text: 'yeah',
          start: const Duration(milliseconds: 450),
          end: const Duration(milliseconds: 520),
        ),
        ForcedAlignedSpan(
          text: 'world',
          start: const Duration(milliseconds: 700),
          end: const Duration(milliseconds: 900),
        ),
      ],
    );

    final outcome = await service.buildReview(
      draft: twoLineDraft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.result.alignmentDiagnostics!.matchedLineCount, 2);
    expect(outcome.result.alignmentDiagnostics!.lineCoverage, 1);
    expect(outcome.result.alignmentDiagnostics!.skippedSpanCount, 1);
    expect(outcome.warning, contains('matched 2 of 2'));
    expect(outcome.warning, contains('Skipped alignment spans: 1'));
    expect(outcome.result.proposedDocument.lines[0].startTime,
        twoLineDraft.lines[0].startTime);
    expect(outcome.result.proposedDocument.lines[1].endTime,
        twoLineDraft.lines[1].endTime);
  });

  test('lists one-based unmatched lyric rows when matching recovers later lines',
      () async {
    final threeLineDraft = LyricDocument(
      language: 'English',
      lines: [
        LyricLine(
          id: 'hello',
          text: 'hello',
          startTime: const Duration(milliseconds: 100),
          endTime: const Duration(milliseconds: 600),
          confidence: 80,
        ),
        LyricLine(
          id: 'missing',
          text: 'missing phrase',
          startTime: const Duration(milliseconds: 700),
          endTime: const Duration(milliseconds: 1300),
          confidence: 42,
        ),
        LyricLine(
          id: 'world',
          text: 'world',
          startTime: const Duration(milliseconds: 1400),
          endTime: const Duration(milliseconds: 2200),
          confidence: 80,
        ),
      ],
    );
    service = ForcedAlignmentProofreadService(
      runner: ({
        required String audioPath,
        required String text,
        required String language,
        required Duration audioDuration,
      }) async => [
        ForcedAlignedSpan(
          text: 'hello',
          start: const Duration(milliseconds: 200),
          end: const Duration(milliseconds: 400),
        ),
        ForcedAlignedSpan(
          text: 'world',
          start: const Duration(milliseconds: 1600),
          end: const Duration(milliseconds: 1800),
        ),
      ],
    );

    final outcome = await service.buildReview(
      draft: threeLineDraft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello missing phrase world',
      language: 'English',
      audioDuration: duration,
    );

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.result.alignmentDiagnostics!.matchedLineCount, 2);
    expect(outcome.result.alignmentDiagnostics!.unmatchedLineNumbers, [2]);
    expect(outcome.warning, contains('matched 2 of 3'));
    expect(outcome.warning, contains('Unmatched lyric lines: 2'));
    expect(outcome.result.lines[0].tokens, isNotEmpty);
    expect(outcome.result.lines[1].tokens, isEmpty);
    expect(outcome.result.lines[2].tokens, isNotEmpty);
    expect(outcome.result.proposedDocument.lines.map((line) => line.text),
        threeLineDraft.lines.map((line) => line.text));
    expect(outcome.result.proposedDocument.lines.map((line) => line.startTime),
        threeLineDraft.lines.map((line) => line.startTime));
  });

  test('treats a successful empty aligner response as zero coverage', () async {
    service = ForcedAlignmentProofreadService(
      runner: ({
        required String audioPath,
        required String text,
        required String language,
        required Duration audioDuration,
      }) async => <ForcedAlignedSpan>[],
    );

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.result.alignmentDiagnostics, isNotNull);
    expect(outcome.result.alignmentDiagnostics!.matchedLineCount, 0);
    expect(outcome.result.alignmentDiagnostics!.lineCoverage, 0);
    expect(outcome.warning, contains('matched 0 of 1'));
    expect(outcome.warning, contains('Unmatched lyric lines: 1'));
    expect(outcome.result.lines.single.tokens, isEmpty);
    expect(outcome.result.proposedDocument.lines.single.text, 'hello world');
    expect(outcome.result.proposedDocument.lines.single.startTime,
        draft.lines.single.startTime);
  });

  test('accepts the managed native runner and preserves review-only semantics', () async {
    service = ForcedAlignmentProofreadService(
      runner: ({
        required String audioPath,
        required String text,
        required String language,
        required Duration audioDuration,
      }) async {
        expect(audioPath, '/tmp/song.wav');
        expect(text, 'hello world');
        expect(language, 'English');
        expect(audioDuration, duration);
        return [
          ForcedAlignedSpan(
            text: 'hello',
            start: const Duration(milliseconds: 200),
            end: const Duration(milliseconds: 600),
          ),
          ForcedAlignedSpan(
            text: 'world',
            start: const Duration(milliseconds: 700),
            end: const Duration(milliseconds: 1100),
          ),
        ];
      },
    );

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );

    expect(outcome.alignmentAvailable, isTrue);
    expect(outcome.result.lines.single.tokens, hasLength(2));
    expect(outcome.result.proposedDocument.lines.single.startTime,
        const Duration(milliseconds: 100));
    expect(outcome.result.proposedDocument.lines.single.endTime,
        const Duration(milliseconds: 1500));
  });

  test('falls back to ordinary proposal when managed runner is unavailable', () async {
    service = ForcedAlignmentProofreadService(
      runner: ({
        required String audioPath,
        required String text,
        required String language,
        required Duration audioDuration,
      }) async => throw Exception('runtime not ready'),
    );

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );

    expect(outcome.alignmentAvailable, isFalse);
    expect(outcome.warning, contains('unavailable'));
    expect(outcome.result.notes, contains('forcedAlignmentUnavailable'));
    expect(outcome.result.proposedDocument.lines.single.startTime,
        const Duration(milliseconds: 100));
  });

  test('keeps review usable and exposes a warning when endpoint fails', () async {
    final responseFuture = server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('runtime unavailable');
      await request.response.close();
    });

    final outcome = await service.buildReview(
      draft: draft,
      audioPath: '/tmp/song.wav',
      referenceText: 'hello world',
      language: 'English',
      audioDuration: duration,
    );
    await responseFuture;

    expect(outcome.alignmentAvailable, isFalse);
    expect(outcome.warning, contains('unavailable'));
    expect(outcome.result.notes, contains('forcedAlignmentUnavailable'));
    expect(outcome.result.proposedDocument.lines.single.text, 'hello world');
    expect(
      outcome.result.proposedDocument.lines.single.startTime,
      const Duration(milliseconds: 100),
    );
    expect(
      outcome.result.lines.single.line.startTime,
      const Duration(milliseconds: 100),
    );
  });
}
