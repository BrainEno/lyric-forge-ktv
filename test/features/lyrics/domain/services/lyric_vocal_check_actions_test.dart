import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_vocal_check_actions.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricVocalCheckSpan _span(int startMs, int endMs) =>
    LyricVocalCheckSpan(_ms(startMs), _ms(endMs));

LyricVocalCheckRemovedLine _removed(String text, int startMs, int endMs) =>
    LyricVocalCheckRemovedLine(
      text: text,
      start: _ms(startMs),
      end: _ms(endMs),
    );

LyricDocument _document(
  List<LyricLine> lines, {
  LyricVocalCheckRecord? record,
  Map<String, dynamic> extra = const {},
}) => LyricDocument(
  language: 'en',
  lines: lines,
  metadata: {
    ...extra,
    if (record != null) LyricVocalCheckRecord.metadataKey: record.toJson(),
  },
);

const _actions = LyricVocalCheckActions();

List<String> _texts(LyricDocument document) => [
  for (final line in document.lines) line.text,
];

void main() {
  group('window', () {
    final draft = _document([
      _line('first line', 10000, 14000, id: 'a'),
      _line('second line', 30000, 34000, id: 'b'),
    ]);

    test('adds context on both sides of a stretch between rows', () {
      final result = _actions.window(draft, _span(20000, 24000));
      expect(result.isUsable, isTrue);
      expect(result.failure, isNull);
      final window = result.window!;
      expect(window.start, _ms(19700));
      expect(window.end, _ms(24300));
      expect(window.length, _ms(4600));
      expect(window.insertAt, 1);
      expect(window.span, _span(20000, 24000));
    });

    test('never reaches into the previous row', () {
      final window = _actions.window(draft, _span(14100, 18000)).window!;
      expect(window.start, _ms(14000));
      expect(window.end, _ms(18300));
    });

    test('never reaches into the next row', () {
      final window = _actions.window(draft, _span(26000, 29900)).window!;
      expect(window.start, _ms(25700));
      expect(window.end, _ms(30000));
    });

    test('a span overlapping a row keeps its own extent', () {
      // The vocal check pads rows by 300 ms, so a stretch can start a
      // little inside a row's span after the user moved that row.
      final window = _actions.window(draft, _span(13500, 18000)).window!;
      expect(window.start, _ms(13500));
      expect(window.insertAt, 1);
    });

    test('before the first row the window starts at most at zero', () {
      final window = _actions.window(draft, _span(100, 6000)).window!;
      expect(window.start, Duration.zero);
      expect(window.end, _ms(6300));
      expect(window.insertAt, 0);
    });

    test('after the last row the window is capped by the audio', () {
      final window = _actions
          .window(draft, _span(40000, 44900), audioDuration: _ms(45000))
          .window!;
      expect(window.start, _ms(39700));
      expect(window.end, _ms(45000));
      expect(window.insertAt, 2);
    });

    test('after the last row without a known length the window is open', () {
      final window = _actions.window(draft, _span(40000, 44900)).window!;
      expect(window.end, _ms(45200));
    });

    test('an audio length before the span keeps the span itself', () {
      final window = _actions
          .window(draft, _span(40000, 44000), audioDuration: _ms(39000))
          .window!;
      expect(window.end, _ms(44000));
    });

    test('a stretch squeezed between rows is too short', () {
      final tight = _document([
        _line('one', 10000, 14000),
        _line('two', 14300, 18000),
      ]);
      final result = _actions.window(tight, _span(14050, 14250));
      expect(result.isUsable, isFalse);
      expect(result.failure, LyricVocalGapWindowFailure.tooShort);
      expect(result.window, isNotNull);
    });

    test('a stretch longer than ninety seconds is too long', () {
      final result = _actions.window(
        _document([_line('one', 0, 1000)]),
        _span(5000, 100000),
      );
      expect(result.isUsable, isFalse);
      expect(result.failure, LyricVocalGapWindowFailure.tooLong);
    });

    test('exactly the limits are usable', () {
      final short = _actions.window(
        _document([_line('one', 0, 1000), _line('two', 1500, 2000)]),
        _span(1000, 1500),
      );
      expect(short.window!.length, LyricVocalCheckActions.minWindow);
      expect(short.isUsable, isTrue);

      final long = _actions.window(
        _document(const []),
        _span(300, 89700),
        audioDuration: _ms(200000),
      );
      expect(long.window!.length, LyricVocalCheckActions.maxWindow);
      expect(long.isUsable, isTrue);
    });

    test('an empty document only has the audio as a limit', () {
      final window = _actions.window(_document(const []), _span(0, 5000));
      expect(window.window!.start, Duration.zero);
      expect(window.window!.insertAt, 0);
    });

    test('rows out of order do not open a window into a row', () {
      // A later row that starts earlier than its predecessor (an unsorted
      // draft) still bounds the window.
      final unsorted = _document([
        _line('one', 10000, 20000),
        _line('two', 22000, 26000),
        _line('three', 21000, 21500),
      ]);
      final window = _actions.window(unsorted, _span(20500, 20900)).window;
      expect(window!.start, _ms(20200));
      expect(window.end, _ms(21000));
    });

    test('the window moves onto the audio with the global offset', () {
      final window = _actions.window(draft, _span(20000, 24000)).window!;
      expect(window.onAudio(_ms(500)), (start: _ms(20200), end: _ms(24800)));
      expect(
        window.onAudio(_ms(-30000)).start,
        Duration.zero,
        reason: 'never before the start of the audio',
      );
    });
  });

  group('insertionIndex', () {
    test('rows starting at the same time keep their order', () {
      final document = _document([
        _line('one', 1000, 2000),
        _line('two', 3000, 4000),
        _line('three', 3000, 5000),
      ]);
      expect(_actions.insertionIndex(document, _ms(500)), 0);
      expect(_actions.insertionIndex(document, _ms(2500)), 1);
      expect(_actions.insertionIndex(document, _ms(3000)), 3);
      expect(_actions.insertionIndex(document, _ms(9000)), 3);
    });
  });

  group('insertion', () {
    const window = LyricVocalGapWindow(
      span: LyricVocalCheckSpan(
        Duration(milliseconds: 20000),
        Duration(milliseconds: 24000),
      ),
      start: Duration(milliseconds: 19700),
      end: Duration(milliseconds: 24300),
      insertAt: 1,
    );

    test('keeps recognised rows inside the window, sorted', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          _line('later words', 22000, 24000),
          _line('earlier words', 19800, 21800),
        ],
      );
      expect(insertion.isEmpty, isFalse);
      expect(insertion.clippedCount, 0);
      expect(
        [for (final line in insertion.newLines) line.text],
        ['earlier words', 'later words'],
      );
      expect(insertion.newLines.every((line) => line.id == null), isTrue);
    });

    test('clips rows that run past the window', () {
      final insertion = _actions.insertion(
        window,
        recognized: [_line('long words', 18000, 26000)],
      );
      final line = insertion.newLines.single;
      expect(line.startTime, _ms(19700));
      expect(line.endTime, _ms(24300));
    });

    test('drops rows outside the window and fragments', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          _line('before', 10000, 12000),
          _line('edge', 24250, 25000),
          _line('kept', 20000, 23000),
        ],
      );
      expect([for (final line in insertion.newLines) line.text], ['kept']);
      expect(insertion.clippedCount, 2);
    });

    test('skips blank text without counting it', () {
      final insertion = _actions.insertion(
        window,
        recognized: [_line('   ', 20000, 21000), _line(' sung ', 21000, 22000)],
      );
      expect(insertion.newLines.single.text, 'sung');
      expect(insertion.clippedCount, 0);
    });

    test('overlapping recognised rows are made consecutive', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          _line('one', 20000, 22000),
          _line('two', 21500, 23500),
          _line('swallowed', 21600, 21900),
        ],
      );
      expect(
        [for (final line in insertion.newLines) line.text],
        ['one', 'two'],
      );
      expect(insertion.newLines[1].startTime, _ms(22000));
      expect(insertion.clippedCount, 1);
    });

    test('keeps confidence and word timing that still fits', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          const LyricLine(
            text: 'hello there',
            startTime: Duration(milliseconds: 20000),
            endTime: Duration(milliseconds: 22000),
            confidence: 64,
            confidenceSource: LyricConfidenceSource.unscored,
            words: [
              LyricWordTiming(
                text: 'hello',
                start: Duration(milliseconds: 20000),
                end: Duration(milliseconds: 20800),
              ),
              LyricWordTiming(
                text: 'there',
                start: Duration(milliseconds: 21000),
                end: Duration(milliseconds: 22000),
              ),
            ],
          ),
        ],
      );
      final line = insertion.newLines.single;
      expect(line.confidence, 64);
      expect(line.confidenceSource, LyricConfidenceSource.unscored);
      expect([for (final word in line.words) word.text], ['hello', 'there']);
    });

    test('clips word timing at the window edges', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          const LyricLine(
            text: 'edge words',
            startTime: Duration(milliseconds: 19000),
            endTime: Duration(milliseconds: 21000),
            words: [
              LyricWordTiming(
                text: 'edge',
                start: Duration(milliseconds: 19500),
                end: Duration(milliseconds: 20000),
              ),
              LyricWordTiming(
                text: 'words',
                start: Duration(milliseconds: 20000),
                end: Duration(milliseconds: 21000),
              ),
            ],
          ),
        ],
      );
      final words = insertion.newLines.single.words;
      expect(words.first.start, _ms(19700));
      expect(words.last.end, _ms(21000));
    });

    test('drops word timing that lost words to the window', () {
      final insertion = _actions.insertion(
        window,
        recognized: [
          const LyricLine(
            text: 'lost words',
            startTime: Duration(milliseconds: 18000),
            endTime: Duration(milliseconds: 21000),
            words: [
              LyricWordTiming(
                text: 'lost',
                start: Duration(milliseconds: 18000),
                end: Duration(milliseconds: 19000),
              ),
              LyricWordTiming(
                text: 'words',
                start: Duration(milliseconds: 20000),
                end: Duration(milliseconds: 21000),
              ),
            ],
          ),
        ],
      );
      expect(insertion.newLines.single.words, isEmpty);
    });

    test('nothing recognised is an empty insertion', () {
      final insertion = _actions.insertion(window, recognized: const []);
      expect(insertion.isEmpty, isTrue);
      final document = _document([_line('one', 0, 1000)]);
      expect(identical(insertion.applyTo(document), document), isTrue);
    });
  });

  group('applyTo', () {
    test('inserts the rows, gives them ids and keeps the others', () {
      final document = _document([
        _line('first line', 10000, 14000, id: 'a'),
        _line('second line', 30000, 34000, id: 'b'),
      ]);
      final window = _actions.window(document, _span(20000, 24000)).window!;
      final insertion = _actions.insertion(
        window,
        recognized: [
          _line('found one', 20000, 22000),
          _line('found two', 22000, 24000),
        ],
      );
      final applied = insertion.applyTo(document);
      expect(_texts(applied), [
        'first line',
        'found one',
        'found two',
        'second line',
      ]);
      expect(applied.lines.first.id, 'a');
      expect(applied.lines.last.id, 'b');
      expect(applied.lines[1].id, isNotNull);
      expect(applied.lines[2].id, isNotNull);
      expect(applied.lines[1].id, isNot(applied.lines[2].id));
    });

    test('row-indexed review evidence moves with later rows', () {
      final document = _document(
        [_line('first line', 10000, 14000), _line('second line', 30000, 34000)],
        extra: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 1, 'text': 'second lime'},
          ],
        },
      );
      final window = _actions.window(document, _span(20000, 24000)).window!;
      final applied = _actions
          .insertion(window, recognized: [_line('found', 20000, 22000)])
          .applyTo(document);
      final candidates =
          applied.metadata[LyricIndexedReviewMetadata.candidatesKey] as List;
      expect((candidates.single as Map)['lineIndex'], 2);
    });

    test('the record stays; the inserted row closes the stretch', () {
      const record = LyricVocalCheckRecord(
        uncoveredSpans: [
          LyricVocalCheckSpan(
            Duration(milliseconds: 20000),
            Duration(milliseconds: 24000),
          ),
        ],
      );
      final document = _document([
        _line('first line', 10000, 14000),
      ], record: record);
      final window = _actions
          .window(document, record.uncoveredSpans.single)
          .window!;
      final applied = _actions
          .insertion(window, recognized: [_line('found', 20500, 23500)])
          .applyTo(document);
      final after = LyricVocalCheckRecord.fromMetadata(applied.metadata)!;
      expect(after.uncoveredSpans, record.uncoveredSpans);
      expect(after.openSpans(applied), isEmpty);
      expect(record.openSpans(document), hasLength(1));
    });

    test('an insertion index past the end appends', () {
      final insertion = LyricVocalGapInsertion(
        window: const LyricVocalGapWindow(
          span: LyricVocalCheckSpan(Duration.zero, Duration(seconds: 1)),
          start: Duration.zero,
          end: Duration(seconds: 1),
          insertAt: 9,
        ),
        newLines: [_line('tail', 0, 1000)],
        clippedCount: 0,
      );
      final applied = insertion.applyTo(_document([_line('one', 0, 500)]));
      expect(_texts(applied), ['one', 'tail']);
    });
  });

  group('dismiss', () {
    const record = LyricVocalCheckRecord(
      retimedLines: 2,
      uncoveredSpans: [
        LyricVocalCheckSpan(Duration(seconds: 20), Duration(seconds: 24)),
        LyricVocalCheckSpan(Duration(seconds: 40), Duration(seconds: 44)),
      ],
    );

    test('takes the stretch off the list and counts it', () {
      final document = _document([_line('one', 0, 1000)], record: record);
      final dismissed = _actions.dismiss(document, record.uncoveredSpans.first);
      final after = LyricVocalCheckRecord.fromMetadata(dismissed.metadata)!;
      expect(after.uncoveredSpans, [record.uncoveredSpans.last]);
      expect(after.dismissedSpans, 1);
      expect(after.retimedLines, 2);
      expect(dismissed.lines, document.lines);
    });

    test('dismissing twice counts both', () {
      var document = _document([_line('one', 0, 1000)], record: record);
      for (final span in record.uncoveredSpans) {
        document = _actions.dismiss(document, span);
      }
      final after = LyricVocalCheckRecord.fromMetadata(document.metadata)!;
      expect(after.uncoveredSpans, isEmpty);
      expect(after.dismissedSpans, 2);
    });

    test('an unknown span or a missing record changes nothing', () {
      final document = _document([_line('one', 0, 1000)], record: record);
      expect(
        identical(_actions.dismiss(document, _span(1, 2)), document),
        isTrue,
      );
      final bare = _document([_line('one', 0, 1000)]);
      expect(
        identical(_actions.dismiss(bare, record.uncoveredSpans.first), bare),
        isTrue,
      );
    });

    test('keeps unrelated metadata', () {
      final document = _document(
        [_line('one', 0, 1000)],
        record: record,
        extra: {'primaryEngine': 'qwen3-asr-1.7b'},
      );
      final dismissed = _actions.dismiss(document, record.uncoveredSpans.first);
      expect(dismissed.metadata['primaryEngine'], 'qwen3-asr-1.7b');
    });
  });

  group('restore', () {
    final record = LyricVocalCheckRecord(
      removedLines: [
        _removed('whispered intro', 1000, 4000),
        _removed('quiet bridge', 50000, 53000),
        _removed('soft outro', 90000, 93000),
      ],
      retimedLines: 1,
    );
    final document = _document([
      _line('verse one', 10000, 14000, id: 'a'),
      _line('verse two', 60000, 64000, id: 'b'),
    ], record: record);

    test('puts chosen rows back at their times', () {
      final restored = _actions.restore(document, {1})!;
      expect(_texts(restored.document), [
        'verse one',
        'quiet bridge',
        'verse two',
      ]);
      expect(restored.restoredIndices, [1]);
      expect(restored.count, 1);
      expect(restored.overlapping, 0);
      final line = restored.document.lines[1];
      expect(line.startTime, _ms(50000));
      expect(line.endTime, _ms(53000));
      expect(line.id, isNotNull);
      expect(restored.restoredIds, {line.id});
    });

    test('updates the record', () {
      final restored = _actions.restore(document, {0, 2})!;
      final after = LyricVocalCheckRecord.fromMetadata(
        restored.document.metadata,
      )!;
      expect(
        [for (final line in after.removedLines) line.text],
        ['quiet bridge'],
      );
      expect(after.restoredLines, 2);
      expect(after.retimedLines, 1);
    });

    test('several rows land in timeline order with their indices', () {
      final restored = _actions.restore(document, {0, 1, 2})!;
      expect(_texts(restored.document), [
        'whispered intro',
        'verse one',
        'quiet bridge',
        'verse two',
        'soft outro',
      ]);
      expect(restored.restoredIndices, [0, 2, 4]);
      expect(restored.restoredIds, hasLength(3));
      expect(restored.document.lines[1].id, 'a');
      expect(restored.document.lines[3].id, 'b');
    });

    test('counts rows that overlap an existing row', () {
      final crowded = _document([
        _line('verse one', 10000, 14000),
        _line('typed by hand', 50500, 52000),
      ], record: record);
      final restored = _actions.restore(crowded, {1})!;
      expect(restored.overlapping, 1);
      expect(_texts(restored.document), [
        'verse one',
        'quiet bridge',
        'typed by hand',
      ]);
    });

    test('row-indexed evidence moves with the rows after a restored row', () {
      final withEvidence = _document(
        [_line('verse one', 10000, 14000), _line('verse two', 60000, 64000)],
        record: record,
        extra: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 0, 'text': 'verse won'},
            {'lineIndex': 1, 'text': 'verse too'},
          ],
        },
      );
      final restored = _actions.restore(withEvidence, {0, 1})!;
      final candidates =
          restored.document.metadata[LyricIndexedReviewMetadata.candidatesKey]
              as List;
      expect(
        [for (final entry in candidates) (entry as Map)['lineIndex']],
        [1, 3],
      );
      expect(restored.document.lines[1].text, 'verse one');
      expect(restored.document.lines[3].text, 'verse two');
    });

    test('unknown positions are ignored; nothing chosen is null', () {
      expect(_actions.restore(document, const {}), isNull);
      expect(_actions.restore(document, {7}), isNull);
      final restored = _actions.restore(document, {0, 7})!;
      expect(restored.count, 1);
    });

    test('no record is null', () {
      expect(_actions.restore(_document([_line('one', 0, 1)]), {0}), isNull);
      expect(_actions.restoreAll(_document([_line('one', 0, 1)])), isNull);
    });

    test('restoreAll puts every row back and empties the list', () {
      final restored = _actions.restoreAll(document)!;
      expect(restored.count, 3);
      final after = LyricVocalCheckRecord.fromMetadata(
        restored.document.metadata,
      )!;
      expect(after.removedLines, isEmpty);
      expect(after.restoredLines, 3);
      expect(_actions.restoreAll(restored.document), isNull);
    });

    test('restoring into an empty document', () {
      final empty = _document(const [], record: record);
      final restored = _actions.restoreAll(empty)!;
      expect(_texts(restored.document), [
        'whispered intro',
        'quiet bridge',
        'soft outro',
      ]);
      expect(restored.restoredIndices, [0, 1, 2]);
    });
  });

  group('record', () {
    final record = LyricVocalCheckRecord(
      removedLines: [_removed('one', 0, 1000), _removed('two', 2000, 3000)],
      retimedLines: 4,
      uncoveredSpans: [_span(5000, 8000), _span(9000, 12000)],
    );

    test('withRestored drops the chosen rows and counts them', () {
      final after = record.withRestored({1, 5});
      expect([for (final line in after.removedLines) line.text], ['one']);
      expect(after.restoredLines, 1);
      expect(after.retimedLines, 4);
      expect(after.uncoveredSpans, record.uncoveredSpans);
      expect(after.withRestored({0}).restoredLines, 2);
    });

    test('withDismissed drops the span and counts it', () {
      final after = record.withDismissed(_span(5000, 8000));
      expect(after.uncoveredSpans, [_span(9000, 12000)]);
      expect(after.dismissedSpans, 1);
      expect(after.removedLines, record.removedLines);
      expect(identical(record.withDismissed(_span(1, 2)), record), isTrue);
    });

    test('the counters survive a round trip and are left out when zero', () {
      expect(record.toJson().containsKey('restoredLines'), isFalse);
      expect(record.toJson().containsKey('dismissedSpans'), isFalse);

      final changed = record.withRestored({0}).withDismissed(_span(5000, 8000));
      final json = changed.toJson();
      expect(json['restoredLines'], 1);
      expect(json['dismissedSpans'], 1);
      final back = LyricVocalCheckRecord.fromMetadata({
        LyricVocalCheckRecord.metadataKey: json,
      })!;
      expect(back.restoredLines, 1);
      expect(back.dismissedSpans, 1);
      expect([for (final line in back.removedLines) line.text], ['two']);
      expect(back.uncoveredSpans, [_span(9000, 12000)]);
    });

    test('malformed counters read as zero', () {
      final back = LyricVocalCheckRecord.fromMetadata({
        LyricVocalCheckRecord.metadataKey: {
          ...record.toJson(),
          'restoredLines': -2,
          'dismissedSpans': 'many',
        },
      })!;
      expect(back.restoredLines, 0);
      expect(back.dismissedSpans, 0);
    });

    test('writeTo stores the record in a new map', () {
      final metadata = <String, dynamic>{'primaryEngine': 'whisper'};
      final written = record.writeTo(metadata);
      expect(metadata.containsKey(LyricVocalCheckRecord.metadataKey), isFalse);
      expect(written['primaryEngine'], 'whisper');
      expect(
        LyricVocalCheckRecord.fromMetadata(written)?.retimedLines,
        record.retimedLines,
      );
    });

    test('a removed row turns back into a row without an id', () {
      final line = _removed(' kept spacing ', 1000, 2000).toLine();
      expect(line.text, ' kept spacing ');
      expect(line.startTime, _ms(1000));
      expect(line.endTime, _ms(2000));
      expect(line.id, isNull);
    });
  });
}
