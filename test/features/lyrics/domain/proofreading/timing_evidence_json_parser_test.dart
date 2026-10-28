import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/timing_evidence_json_parser.dart';

void main() {
  const parser = TimingEvidenceJsonParser();

  test('parses a lyric document and preserves timing confidence', () {
    final result = parser.parse('''
      {
        "language": "en",
        "lines": [
          {
            "text": "hello world",
            "startTime": 1200,
            "endTime": 2600,
            "confidence": 84,
            "isChorus": false,
            "id": "asr-line-1"
          }
        ],
        "globalOffset": 0,
        "metadata": {"generatedBy": "independent-asr"}
      }
    ''');

    expect(result.lines.single.text, 'hello world');
    expect(result.lines.single.startTime.inMilliseconds, 1200);
    expect(result.lines.single.endTime.inMilliseconds, 2600);
    expect(result.lines.single.confidence, 84);
    expect(result.lines.single.id, 'asr-line-1');
    expect(result.metadata['generatedBy'], 'independent-asr');
  });

  test('accepts a project manifest wrapper without discarding confidence', () {
    final result = parser.parse('''
      {
        "id": "project-2",
        "lyricDocument": {
          "language": "ja",
          "lines": [
            {
              "text": "こんにちは",
              "startTime": 500,
              "endTime": 1400,
              "confidence": 73
            }
          ],
          "metadata": {}
        }
      }
    ''');

    expect(result.language, 'ja');
    expect(result.lines.single.confidence, 73);
  });

  test('rejects empty, malformed and invalid timing evidence', () {
    expect(() => parser.parse('[]'), throwsFormatException);
    expect(() => parser.parse('{"language":"en","lines":[]}'), throwsFormatException);
    expect(
      () => parser.parse('''
        {
          "language": "en",
          "lines": [
            {
              "text": "bad",
              "startTime": 2000,
              "endTime": 1000,
              "confidence": 90
            }
          ]
        }
      '''),
      throwsFormatException,
    );
    expect(
      () => parser.parse('''
        {
          "language": "en",
          "lines": [
            {
              "text": "bad",
              "startTime": 0,
              "endTime": 1000,
              "confidence": 120
            }
          ]
        }
      '''),
      throwsFormatException,
    );
  });
}
