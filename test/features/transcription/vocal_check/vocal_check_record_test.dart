import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs));

void main() {
  const record = LyricVocalCheckRecord(
    removedLines: [
      LyricVocalCheckRemovedLine(
        text: '谢谢观看',
        start: Duration(seconds: 2),
        end: Duration(seconds: 5),
      ),
    ],
    retimedLines: 4,
    uncoveredSpans: [
      LyricVocalCheckSpan(Duration(seconds: 40), Duration(seconds: 44)),
      LyricVocalCheckSpan(Duration(seconds: 90), Duration(seconds: 93)),
    ],
  );

  test('round-trips through document metadata', () {
    final metadata = <String, dynamic>{
      LyricVocalCheckRecord.metadataKey: record.toJson(),
    };
    final restored = LyricVocalCheckRecord.fromMetadata(metadata)!;
    expect(restored.retimedLines, 4);
    expect(restored.removedLines.single.text, '谢谢观看');
    expect(restored.removedLines.single.start, const Duration(seconds: 2));
    expect(restored.removedLines.single.end, const Duration(seconds: 5));
    expect(restored.uncoveredSpans, record.uncoveredSpans);
    expect(restored.changedDraft, isTrue);
    expect(restored.isEmpty, isFalse);
  });

  test('stores times as whole milliseconds', () {
    final json = record.toJson();
    expect(json['schemaVersion'], 1);
    expect(json['uncoveredSpans'], [
      [40000, 44000],
      [90000, 93000],
    ]);
    expect((json['removedLines'] as List).single, {
      'text': '谢谢观看',
      'startMs': 2000,
      'endMs': 5000,
    });
  });

  test('absent, foreign or newer records read as none', () {
    expect(LyricVocalCheckRecord.fromMetadata(const {}), isNull);
    expect(
      LyricVocalCheckRecord.fromMetadata(const {'vocalCheck': 'yes'}),
      isNull,
    );
    expect(
      LyricVocalCheckRecord.fromMetadata(const {
        'vocalCheck': {'schemaVersion': 2, 'retimedLines': 3},
      }),
      isNull,
    );
  });

  test('malformed entries are skipped, the rest kept', () {
    final restored = LyricVocalCheckRecord.fromMetadata(const {
      'vocalCheck': {
        'schemaVersion': 1,
        'retimedLines': -3,
        'removedLines': [
          {'text': 'kept', 'startMs': 0, 'endMs': 900},
          {'text': 'end before start', 'startMs': 900, 'endMs': 100},
          {'startMs': 0, 'endMs': 100},
          'garbage',
        ],
        'uncoveredSpans': [
          [1000, 2000],
          [3000, 3000],
          [-5, 10],
          [1, 2, 3],
          'x',
        ],
      },
    })!;
    expect(restored.retimedLines, 0);
    expect(restored.removedLines.map((line) => line.text), ['kept']);
    expect(restored.uncoveredSpans, [
      LyricVocalCheckSpan(_ms(1000), _ms(2000)),
    ]);
  });

  test('an empty record says nothing changed', () {
    const empty = LyricVocalCheckRecord();
    expect(empty.isEmpty, isTrue);
    expect(empty.changedDraft, isFalse);
    expect(
      empty.openSpans(LyricDocument(language: 'en', lines: [_line('a', 0, 1)])),
      isEmpty,
    );
  });

  group('openSpans', () {
    test('every stretch is open while no row is near it', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_line('前面', 30000, 38000), _line('后面', 60000, 70000)],
      );
      expect(record.openSpans(document), record.uncoveredSpans);
    });

    test('a row added over a stretch closes it', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_line('补上的歌词', 41000, 43500)],
      );
      expect(record.openSpans(document), [record.uncoveredSpans.last]);
    });

    test('a row just outside a stretch, within the tolerance, closes it', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_line('紧挨着', 44200, 46000)],
      );
      expect(record.openSpans(document), [record.uncoveredSpans.last]);
      expect(
        record.openSpans(document, tolerance: Duration.zero),
        record.uncoveredSpans,
      );
    });

    test('empty or untimed rows do not close a stretch', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [
          _line('   ', 40000, 44000),
          _line('没有时长', 91000, 91000),
        ],
      );
      expect(record.openSpans(document), record.uncoveredSpans);
    });
  });
}
