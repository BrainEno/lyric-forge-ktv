import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_json_transcript_parser.dart';

// Every lyric below is synthetic text written for these tests.
Map<String, Object?> token(String text, int from, int to) => {
  'text': text,
  'p': 0.9,
  'offsets': {'from': from, 'to': to},
};

String response(String text, List<Object?> tokens) => jsonEncode({
  'result': {'language': 'zh'},
  'transcription': [
    {
      'text': text,
      'offsets': {'from': 1000, 'to': 3000},
      'tokens': tokens,
    },
  ],
});

List<(String, int, int)> wordsOf(String json) => [
  for (final word
      in const WhisperJsonTranscriptParser()
          .parse(json)
          .document
          .lines
          .single
          .words)
    (word.text, word.start.inMilliseconds, word.end.inMilliseconds),
];

void main() {
  test('Latin pieces join into words and control tokens are skipped', () {
    expect(
      wordsOf(
        response(' hold me, tight', [
          token('[_BEG_]', 1000, 1000),
          token(' ho', 1000, 1200),
          token('ld', 1200, 1400),
          token(' me', 1400, 1800),
          token(',', 1800, 1800),
          token(' tight', 1900, 2900),
          token('[_TT_150]', 2900, 2900),
        ]),
      ),
      [('hold', 1000, 1400), ('me,', 1400, 1800), ('tight', 1900, 2900)],
    );
  });

  test('a Han character always starts a new word', () {
    expect(
      wordsOf(
        response('我爱你', [
          token('我', 1000, 1300),
          token('爱你', 1300, 2000),
        ]),
      ),
      [('我', 1000, 1300), ('爱你', 1300, 2000)],
    );
    expect(
      wordsOf(
        response('爱 you', [
          token('爱', 1000, 1300),
          token(' you', 1300, 2000),
        ]),
      ),
      [('爱', 1000, 1300), ('you', 1300, 2000)],
    );
  });

  test('broken UTF-8, missing offsets or a mismatch drop the words', () {
    expect(
      wordsOf(
        response('我爱你', [
          token('我', 1000, 1300),
          token('\uFFFD', 1300, 1500),
          token('\uFFFD', 1500, 2000),
        ]),
      ),
      isEmpty,
    );
    expect(
      wordsOf(
        response('我爱你', [
          token('我', 1000, 1300),
          {'text': '爱你', 'p': 0.9},
        ]),
      ),
      isEmpty,
    );
    expect(
      wordsOf(
        response('我爱你们', [
          token('我', 1000, 1300),
          token('爱你', 1300, 2000),
        ]),
      ),
      isEmpty,
    );
  });

  test('segments without token offsets keep their old shape', () {
    final json = jsonEncode({
      'result': {'language': 'en'},
      'transcription': [
        {
          'text': 'hello',
          'offsets': {'from': 0, 'to': 1000},
          'tokens': [
            {'text': 'hello', 'p': 0.9},
          ],
        },
      ],
    });
    expect(wordsOf(json), isEmpty);
  });
}
