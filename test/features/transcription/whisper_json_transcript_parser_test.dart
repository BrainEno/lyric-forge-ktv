import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_json_transcript_parser.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

Map<String, Object?> segment({
  Object? text = 'hello world',
  Object? from = 1200,
  Object? to = 2800,
  Object? tokens = const [
    {'text': ' hello', 'p': 0.8},
    {'text': ' world', 'p': 0.6},
  ],
}) => {
  'text': text,
  'offsets': {'from': from, 'to': to},
  if (tokens != null) 'tokens': tokens,
};

Map<String, Object?> response(
  List<Object?> segments, {
  Object? language = 'en',
}) => {
  'result': {'language': language},
  'transcription': segments,
};

void main() {
  const parser = WhisperJsonTranscriptParser();

  group('whisper.cpp response mapping', () {
    test('retains line time, text, token score and source path', () {
      final parsed = parser.parse(
        jsonEncode(response([segment()], language: ' en ')),
        rawJsonPath: '/tmp/whisper.json',
      );

      expect(parsed.detectedLanguage, 'en');
      expect(parsed.inputSegmentCount, 1);
      expect(parsed.skippedSegmentCount, 0);
      expect(parsed.lowConfidenceCount, 0);
      expect(parsed.document.language, 'en');
      expect(parsed.document.metadata['rawJsonPath'], '/tmp/whisper.json');
      expect(parsed.document.lines.single.text, 'hello world');
      expect(
        parsed.document.lines.single.startTime,
        const Duration(milliseconds: 1200),
      );
      expect(
        parsed.document.lines.single.endTime,
        const Duration(milliseconds: 2800),
      );
      expect(parsed.document.lines.single.confidence, 70);
      expect(
        parsed.document.lines.single.confidenceSource,
        LyricConfidenceSource.model,
      );
    });

    test('keeps unscored lines distinct from low-confidence model output', () {
      final parsed = parser.parse(
        jsonEncode(
          response([
            segment(tokens: null),
            segment(
              text: 'one weak line',
              from: 3200,
              to: 4700,
              tokens: [
                {'text': ' weak', 'p': 0.2},
              ],
            ),
            segment(
              text: 'text survives malformed score data',
              from: 5000,
              to: 7000,
              tokens: [
                {'text': 7, 'p': 0.1},
              ],
            ),
          ]),
        ),
      );

      expect(
        parsed.document.lines.first.confidence,
        unscoredConfidencePlaceholder,
      );
      expect(
        parsed.document.lines.first.confidenceSource,
        LyricConfidenceSource.unscored,
      );
      expect(parsed.document.lines[1].confidence, 20);
      expect(
        parsed.document.lines[1].confidenceSource,
        LyricConfidenceSource.model,
      );
      expect(
        parsed.document.lines.last.text,
        'text survives malformed score data',
      );
      expect(
        parsed.document.lines.last.confidenceSource,
        LyricConfidenceSource.unscored,
      );
      expect(parsed.lowConfidenceCount, 1);
    });

    test('skips malformed segments and reports the count', () {
      final parsed = parser.parse(
        jsonEncode(
          response([
            null,
            'not a segment',
            segment(text: '  '),
            segment(text: 99),
            segment(from: -1),
            segment(from: 500, to: 500),
            segment(
              from: WhisperJsonTranscriptParser.maxTimelineMilliseconds + 1,
            ),
            segment(),
          ]),
        ),
      );

      expect(parsed.inputSegmentCount, 8);
      expect(parsed.skippedSegmentCount, 7);
      expect(parsed.document.lines.single.text, 'hello world');
    });

    test('uses unknown language for absent or untrusted language metadata', () {
      for (final language in [null, 42, '', List.filled(65, 'x').join()]) {
        final parsed = parser.parse(
          jsonEncode(response([segment()], language: language)),
        );
        expect(parsed.detectedLanguage, 'unknown');
      }
    });

    test('bounds JSON size, segment count and text length', () {
      expect(
        () => const WhisperJsonTranscriptParser(
          maxJsonCharacters: 4,
        ).parse(jsonEncode(response([segment()]))),
        throwsA(isA<TranscriptionException>()),
      );
      expect(
        () => const WhisperJsonTranscriptParser(maxSegments: 1).parse(
          jsonEncode(response([segment(), segment(from: 3000, to: 4000)])),
        ),
        throwsA(isA<TranscriptionException>()),
      );
      final textLimited =
          const WhisperJsonTranscriptParser(maxTextRunesPerLine: 4).parse(
            jsonEncode(
              response([
                segment(text: 'line too long'),
                segment(text: 'ok', from: 3000, to: 4000),
              ]),
            ),
          );
      expect(textLimited.skippedSegmentCount, 1);
      expect(textLimited.document.lines.single.text, 'ok');
    });
  });

  group('invalid response envelopes', () {
    test(
      'rejects malformed JSON and non-object roots as environment errors',
      () {
        for (final source in ['{broken', '[]', 'null', '"text"']) {
          expect(
            () => parser.parse(source),
            throwsA(
              isA<TranscriptionException>().having(
                (error) => error.kind,
                'kind',
                TranscriptionFailureKind.environment,
              ),
            ),
          );
        }
      },
    );

    test('requires transcription list and at least one usable line', () {
      expect(
        () => parser.parse(
          jsonEncode({
            'result': {'language': 'en'},
          }),
        ),
        throwsA(isA<TranscriptionException>()),
      );
      expect(
        () => parser.parse(jsonEncode(response([segment(text: ' ')]))),
        throwsA(
          isA<TranscriptionException>().having(
            (error) => error.kind,
            'kind',
            TranscriptionFailureKind.input,
          ),
        ),
      );
    });
  });
}
