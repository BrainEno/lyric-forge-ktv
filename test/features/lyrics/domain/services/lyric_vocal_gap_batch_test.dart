import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_vocal_check_actions.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_vocal_gap_batch.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricVocalCheckSpan _span(int startMs, int endMs) =>
    LyricVocalCheckSpan(_ms(startMs), _ms(endMs));

const _batch = LyricVocalGapBatch();
const _actions = LyricVocalCheckActions();

final _spans = [
  _span(40000, 43000),
  _span(20000, 24000),
  _span(60000, 63000),
  _span(16000, 18000),
];

LyricDocument _draft({
  List<LyricVocalCheckSpan>? spans,
  Map<String, dynamic> extra = const {},
  List<LyricLine>? lines,
}) => LyricDocument(
  language: 'en',
  lines:
      lines ??
      [
        _line('verse one', 10000, 14000, id: 'a'),
        _line('verse two', 30000, 34000, id: 'b'),
        _line('verse three', 50000, 54000, id: 'c'),
      ],
  metadata: {
    ...extra,
    LyricVocalCheckRecord.metadataKey: LyricVocalCheckRecord(
      retimedLines: 1,
      uncoveredSpans: spans ?? _spans,
    ).toJson(),
  },
);

List<String> _texts(LyricDocument document) => [
  for (final line in document.lines) line.text,
];

/// What a recogniser would return for [item]: [lines] clipped into its
/// window.
LyricVocalGapInsertion _insertion(
  LyricVocalGapBatchItem item,
  List<LyricLine> lines,
) => _actions.insertion(item.window!, recognized: lines);

LyricVocalGapInsertion _manual(
  int insertAt,
  int windowStartMs,
  List<LyricLine> lines,
) => LyricVocalGapInsertion(
  window: LyricVocalGapWindow(
    span: _span(windowStartMs, windowStartMs + 1000),
    start: _ms(windowStartMs),
    end: _ms(windowStartMs + 10000),
    insertAt: insertAt,
  ),
  newLines: lines,
  clippedCount: 0,
);

void main() {
  group('plan', () {
    test('one window per stretch, in timeline order', () {
      final plan = _batch.plan(_draft(), _spans);
      expect([for (final item in plan.items) item.span], [
        _span(16000, 18000),
        _span(20000, 24000),
        _span(40000, 43000),
        _span(60000, 63000),
      ]);
      expect([for (final item in plan.items) item.window!.insertAt], [
        1,
        1,
        2,
        3,
      ]);
      expect(plan.items[0].window!.start, _ms(15700));
      expect(plan.items[0].window!.end, _ms(18300));
      expect(plan.sendableCount, 4);
      expect(plan.skippedCount, 0);
      expect(plan.isEmpty, isFalse);
    });

    test('stretches that cannot be sent are kept with the reason', () {
      final squeezed = _span(14050, 14250);
      final plan = _batch.plan(
        _draft(
          lines: [_line('one', 10000, 14000), _line('two', 14300, 18000)],
        ),
        [squeezed, _span(30000, 33000)],
      );
      expect(plan.items.first.isSendable, isFalse);
      expect(plan.items.first.failure, LyricVocalGapWindowFailure.tooShort);
      expect(plan.items.last.isSendable, isTrue);
      expect(plan.sendableCount, 1);
      expect(plan.skippedCount, 1);
    });

    test('the audio length caps the last window', () {
      final plan = _batch.plan(_draft(), [
        _span(60000, 63000),
      ], audioDuration: _ms(63100));
      expect(plan.items.single.window!.end, _ms(63100));
    });

    test('no stretches, empty plan', () {
      final plan = _batch.plan(_draft(), const []);
      expect(plan.isEmpty, isTrue);
      expect(plan.sendableCount, 0);
    });
  });

  group('apply', () {
    final document = _draft();
    final plan = _batch.plan(document, _spans);

    test('inserts the rows of every stretch in one edit', () {
      final result = _batch.apply(
        document,
        insertions: [
          _insertion(plan.items[2], [_line('found at forty', 40000, 42500)]),
          _insertion(plan.items[1], [
            _line('found at twenty', 20000, 22000),
            _line('and more', 22000, 24000),
          ]),
          _insertion(plan.items[3], [_line('found at sixty', 60000, 62000)]),
        ],
      )!;
      expect(_texts(result.document), [
        'verse one',
        'found at twenty',
        'and more',
        'verse two',
        'found at forty',
        'verse three',
        'found at sixty',
      ]);
      expect(result.insertedIndices, [1, 2, 4, 6]);
      expect(result.insertedCount, 4);
      expect(result.filledGaps, 3);
      expect(result.dismissedGaps, 0);
      expect(result.document.lines[0].id, 'a');
      expect(result.document.lines[3].id, 'b');
      expect(result.document.lines[5].id, 'c');
      final ids = {
        for (final index in result.insertedIndices)
          result.document.lines[index].id,
      };
      expect(ids, hasLength(4));
      expect(ids, isNot(contains(null)));
    });

    test('closes the filled stretches and leaves the rest open', () {
      final result = _batch.apply(
        document,
        insertions: [
          _insertion(plan.items[1], [_line('found', 20200, 23800)]),
        ],
      )!;
      final record = LyricVocalCheckRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(record.uncoveredSpans, hasLength(4));
      // In the record's order, as recognition stored them.
      expect(record.openSpans(result.document), [
        _span(40000, 43000),
        _span(60000, 63000),
        _span(16000, 18000),
      ]);
    });

    test('matches inserting one stretch on its own', () {
      final insertion = _insertion(plan.items[2], [
        _line('found', 40000, 42000),
      ]);
      final alone = insertion.applyTo(document);
      final batched = _batch.apply(document, insertions: [insertion])!;
      expect(_texts(batched.document), _texts(alone));
      expect(batched.insertedIndices, [2]);
    });

    test('two stretches between the same rows keep their order', () {
      final result = _batch.apply(
        document,
        insertions: [
          _insertion(plan.items[1], [_line('later gap', 20000, 23000)]),
          _insertion(plan.items[0], [_line('earlier gap', 16000, 18000)]),
        ],
      )!;
      expect(_texts(result.document).sublist(0, 4), [
        'verse one',
        'earlier gap',
        'later gap',
        'verse two',
      ]);
      expect(result.insertedIndices, [1, 2]);
      expect(result.filledGaps, 2);
    });

    test('overlapping rows of neighbouring stretches are made consecutive', () {
      final result = _batch.apply(
        document,
        insertions: [
          _manual(1, 15000, [_line('first', 15000, 19000)]),
          _manual(1, 18000, [_line('second', 18000, 20000)]),
          _manual(1, 18500, [_line('swallowed', 18500, 20050)]),
        ],
      )!;
      expect(_texts(result.document).sublist(0, 4), [
        'verse one',
        'first',
        'second',
        'verse two',
      ]);
      expect(result.document.lines[2].startTime, _ms(19000));
      expect(result.document.lines[2].endTime, _ms(20000));
      expect(result.filledGaps, 2, reason: 'the swallowed one added no row');
    });

    test('rows separated by an existing row are not trimmed', () {
      final result = _batch.apply(
        document,
        insertions: [
          _manual(1, 15000, [_line('before b', 15000, 29000)]),
          _manual(2, 15000, [_line('after b', 15000, 29000)]),
        ],
      )!;
      expect(result.document.lines[3].startTime, _ms(15000));
    });

    test('empty insertions are ignored; nothing to do is null', () {
      final empty = _actions.insertion(plan.items[1].window!, recognized: []);
      expect(_batch.apply(document, insertions: [empty]), isNull);
      expect(_batch.apply(document, insertions: const []), isNull);
      final result = _batch.apply(
        document,
        insertions: [
          empty,
          _insertion(plan.items[2], [_line('found', 40000, 42000)]),
        ],
      )!;
      expect(result.filledGaps, 1);
    });

    test('an insertion index past the end appends', () {
      final result = _batch.apply(
        document,
        insertions: [
          _manual(9, 70000, [_line('tail', 70000, 72000)]),
        ],
      )!;
      expect(_texts(result.document).last, 'tail');
      expect(result.insertedIndices, [3]);
    });

    test('row-indexed review evidence moves with the old rows', () {
      final withEvidence = _draft(
        extra: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 0, 'text': 'verse won'},
            {'lineIndex': 1, 'text': 'verse too'},
            {'lineIndex': 2, 'text': 'verse tree'},
          ],
          LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [2],
        },
      );
      final evidencePlan = _batch.plan(withEvidence, _spans);
      final result = _batch.apply(
        withEvidence,
        insertions: [
          _insertion(evidencePlan.items[1], [_line('found', 20000, 22000)]),
          _insertion(evidencePlan.items[2], [_line('found', 40000, 42000)]),
        ],
      )!;
      final metadata = result.document.metadata;
      final candidates =
          metadata[LyricIndexedReviewMetadata.candidatesKey] as List;
      expect([for (final entry in candidates) (entry as Map)['lineIndex']], [
        0,
        2,
        4,
      ]);
      expect(metadata[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey], [
        4,
      ]);
      for (final entry in candidates) {
        final map = entry as Map;
        final line = result.document.lines[map['lineIndex'] as int];
        expect(map['text'], startsWith(line.text.substring(0, 5)));
      }
    });

    test('evidence pointing past the rows is dropped', () {
      final malformed = _draft(
        extra: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 1, 'text': 'verse too'},
            {'lineIndex': 7, 'text': 'nowhere'},
          ],
        },
      );
      final result = _batch.apply(
        malformed,
        insertions: [
          _manual(1, 20000, [_line('found', 20000, 22000)]),
        ],
      )!;
      final candidates =
          result.document.metadata[LyricIndexedReviewMetadata.candidatesKey]
              as List;
      expect([for (final entry in candidates) (entry as Map)['lineIndex']], [
        2,
      ]);
    });
  });

  group('dismiss', () {
    final document = _draft();
    final plan = _batch.plan(document, _spans);

    test('marks stretches without lyrics and leaves the rows alone', () {
      final result = _batch.apply(
        document,
        insertions: const [],
        dismiss: [_span(16000, 18000), _span(60000, 63000)],
      )!;
      expect(result.insertedCount, 0);
      expect(result.dismissedGaps, 2);
      expect(result.document.lines, document.lines);
      final record = LyricVocalCheckRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(record.uncoveredSpans, [_span(40000, 43000), _span(20000, 24000)]);
      expect(record.dismissedSpans, 2);
      expect(record.retimedLines, 1);
    });

    test('unknown stretches are not counted', () {
      expect(
        _batch.apply(document, insertions: const [], dismiss: [_span(1, 2)]),
        isNull,
      );
      final result = _batch.apply(
        document,
        insertions: const [],
        dismiss: [_span(1, 2), _span(20000, 24000), _span(20000, 24000)],
      )!;
      expect(result.dismissedGaps, 1);
    });

    test('without a record nothing is dismissed', () {
      final bare = LyricDocument(
        language: 'en',
        lines: [_line('one', 0, 1000)],
      );
      expect(
        _batch.apply(bare, insertions: const [], dismiss: [_span(1, 2)]),
        isNull,
      );
    });

    test('inserting and dismissing in one edit', () {
      final result = _batch.apply(
        document,
        insertions: [
          _insertion(plan.items[1], [_line('found', 20000, 23000)]),
        ],
        dismiss: [_span(60000, 63000)],
      )!;
      expect(result.insertedIndices, [1]);
      expect(result.dismissedGaps, 1);
      final record = LyricVocalCheckRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(record.openSpans(result.document), [
        _span(40000, 43000),
        _span(16000, 18000),
      ]);
    });
  });

  group('helpers', () {
    test('the other engine', () {
      expect(lyricOtherSpanEngine(LyricSpanEngine.qwen), LyricSpanEngine.whisper);
      expect(lyricOtherSpanEngine(LyricSpanEngine.whisper), LyricSpanEngine.qwen);
    });

    test('recognised rows move onto the document timeline', () {
      final moved = LyricVocalCheckActions.toDocumentTimeline([
        const LyricLine(
          text: 'shifted',
          startTime: Duration(milliseconds: 20500),
          endTime: Duration(milliseconds: 22500),
          confidence: 70,
          words: [
            LyricWordTiming(
              text: 'shifted',
              start: Duration(milliseconds: 20500),
              end: Duration(milliseconds: 22500),
            ),
          ],
        ),
      ], _ms(500));
      final line = moved.single;
      expect(line.startTime, _ms(20000));
      expect(line.endTime, _ms(22000));
      expect(line.words.single.start, _ms(20000));
      expect(line.words.single.end, _ms(22000));
      expect(line.confidence, 70);
      expect(line.text, 'shifted');
    });

    test('no offset keeps the times', () {
      final lines = [_line('same', 1000, 2000)];
      final moved = LyricVocalCheckActions.toDocumentTimeline(
        lines,
        Duration.zero,
      );
      expect(moved.single.startTime, _ms(1000));
      expect(moved.single.endTime, _ms(2000));
    });
  });
}
