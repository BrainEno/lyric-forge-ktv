import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_gap_fill_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _s(double value) => Duration(milliseconds: (value * 1000).round());

LyricLine _line(String text, double start, double end, String id) =>
    LyricLine(text: text, startTime: _s(start), endTime: _s(end), id: id);

const _filled = LyricVocalGapFillRecord(
  insertedLineIds: ['auto-1', 'auto-2'],
  filledSpans: [
    LyricVocalCheckSpan(Duration(seconds: 20), Duration(seconds: 24)),
  ],
  emptySpans: 1,
  failedSpans: 0,
  unattemptedSpans: 2,
  fallbackSpans: 1,
);

LyricDocument _document({
  LyricVocalGapFillRecord? record = _filled,
  List<LyricLine>? lines,
}) {
  var metadata = <String, dynamic>{
    'primaryEngine': 'qwen3-asr-1.7b',
    ...const LyricVocalCheckRecord(
      uncoveredSpans: [
        LyricVocalCheckSpan(Duration(seconds: 20), Duration(seconds: 24)),
      ],
    ).writeTo(const {}),
  };
  if (record != null) metadata = record.writeTo(metadata);
  return LyricDocument(
    language: 'zh',
    lines:
        lines ??
        [
          _line('第一句', 10, 15, 'a'),
          _line('补上的一', 20, 22, 'auto-1'),
          _line('补上的二', 22, 24, 'auto-2'),
          _line('最后一句', 30, 35, 'b'),
        ],
    metadata: metadata,
  );
}

RecognitionReviewSummary _summary(LyricDocument document) =>
    RecognitionReviewSummary.fromDocument(
      document,
      LyricReviewQueue.build(document),
    );

void main() {
  group('LyricVocalGapFillRecord', () {
    test('survives a metadata round trip', () {
      final restored = LyricVocalGapFillRecord.fromMetadata(
        _filled.writeTo(const {'other': 1}),
      )!;
      expect(restored.insertedLineIds, ['auto-1', 'auto-2']);
      expect(restored.filledSpans, _filled.filledSpans);
      expect(restored.emptySpans, 1);
      expect(restored.unattemptedSpans, 2);
      expect(restored.fallbackSpans, 1);
      expect(restored.totalSpans, 4);
      expect(restored.isEmpty, isFalse);
    });

    test('ignores other schemas and skips malformed entries', () {
      expect(LyricVocalGapFillRecord.fromMetadata(const {}), isNull);
      expect(
        LyricVocalGapFillRecord.fromMetadata(const {
          'vocalGapFill': {'schemaVersion': 2},
        }),
        isNull,
      );
      final record = LyricVocalGapFillRecord.fromMetadata(const {
        'vocalGapFill': {
          'schemaVersion': 1,
          'insertedLineIds': ['x', 3, '', null],
          'filledSpans': [
            [1000, 2000],
            [5, 1],
            'bad',
          ],
          'emptySpans': -4,
          'failedSpans': 'two',
        },
      })!;
      expect(record.insertedLineIds, ['x']);
      expect(record.filledSpans, hasLength(1));
      expect(record.emptySpans, 0);
      expect(record.failedSpans, 0);
    });

    test('finds its rows by id after other rows move', () {
      final document = _document();
      final moved = document.copyWith(
        lines: [_line('新加的', 0, 5, 'n'), ...document.lines],
      );
      expect(_filled.insertedIndices(document), [1, 2]);
      expect(_filled.insertedIndices(moved), [2, 3]);
    });

    test('a deleted or emptied row drops out', () {
      final document = _document(
        lines: [
          _line('第一句', 10, 15, 'a'),
          _line('  ', 20, 22, 'auto-1'),
          _line('最后一句', 30, 35, 'b'),
        ],
      );
      expect(_filled.insertedIndices(document), isEmpty);
    });
  });

  group('review queue', () {
    test('puts every auto-filled row in the queue', () {
      final document = _document();
      final ranked = const LyricReviewPriorityService().rank(document);
      final byIndex = {for (final item in ranked) item.lineIndex: item};
      for (final index in [1, 2]) {
        expect(
          byIndex[index]?.reasons.map((reason) => reason.code),
          contains(LyricReviewPriorityReasonCode.vocalGapFillInserted),
        );
      }
      expect(byIndex.containsKey(0), isFalse);
      expect(byIndex.containsKey(3), isFalse);
    });

    test('a confirmed row leaves the queue', () {
      final document = const LyricReviewDecisionService().setReviewed(
        _document(),
        1,
        reviewed: true,
      );
      final indices = const LyricReviewPriorityService()
          .rank(document)
          .map((item) => item.lineIndex);
      expect(indices, [2]);
    });

    test('documents without the record are ranked as before', () {
      final ranked = const LyricReviewPriorityService().rank(
        _document(record: null),
      );
      expect(ranked, isEmpty);
    });

    test('the reason has a label', () {
      expect(
        LyricReviewStrings.priorityReason(
          const LyricReviewPriorityReason(
            LyricReviewPriorityReasonCode.vocalGapFillInserted,
          ),
        ),
        '识别时按人声自动补上的漏句，建议试听确认',
      );
    });
  });

  group('summary', () {
    test('counts the auto-filled rows still there and unconfirmed', () {
      final document = const LyricReviewDecisionService().setReviewed(
        _document(),
        2,
        reviewed: true,
      );
      final summary = _summary(document);
      expect(summary.vocalGapFill, isNotNull);
      expect(summary.autoFilledLines, 2);
      expect(summary.pendingAutoFilledLines, 1);
      // The rows close the vocal check's stretch.
      expect(summary.openVocalSpans, isEmpty);
    });

    test('no record, or one that inserted nothing, is not shown', () {
      expect(_summary(_document(record: null)).vocalGapFill, isNull);
      expect(
        _summary(
          _document(record: const LyricVocalGapFillRecord(emptySpans: 3)),
        ).vocalGapFill,
        isNull,
      );
    });

    test('describes what the step did', () {
      final lines = LyricRecognitionSummaryCard.vocalGapFillLines(
        _summary(_document()),
      );
      expect(lines, hasLength(2));
      expect(lines.first, contains('自动补上 1 处漏句（其中 1 处由第二个引擎补上）'));
      expect(lines.first, contains('列入待复核'));
      expect(lines.last, '自动补句：1 处没有识别出文字、2 处未自动识别');
    });

    test('a clean fill has a single line', () {
      final lines = LyricRecognitionSummaryCard.vocalGapFillLines(
        _summary(
          _document(
            record: const LyricVocalGapFillRecord(
              insertedLineIds: ['auto-1'],
              filledSpans: [
                LyricVocalCheckSpan(Duration(seconds: 20), Duration(seconds: 24)),
              ],
            ),
          ),
        ),
      );
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains('第二个引擎')));
      expect(
        LyricRecognitionSummaryCard.vocalGapFillLines(
          _summary(_document(record: null)),
        ),
        isEmpty,
      );
    });
  });

  group('card', () {
    Future<void> pump(WidgetTester tester, LyricDocument document) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricRecognitionSummaryCard(
                  summary: _summary(document),
                  onStartReview: null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows how many auto-filled rows wait for a listen', (
      tester,
    ) async {
      await pump(tester, _document());
      expect(find.textContaining('自动补句', findRichText: true), findsOneWidget);
      expect(find.textContaining('2/2 行待听', findRichText: true), findsOneWidget);
      expect(find.textContaining('列入待复核'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('列入待复核'), findsOneWidget);
    });

    testWidgets('all confirmed shows the plain count', (tester) async {
      var document = _document();
      for (final index in [1, 2]) {
        document = const LyricReviewDecisionService().setReviewed(
          document,
          index,
          reviewed: true,
        );
      }
      await pump(tester, document);
      expect(find.textContaining('2 行', findRichText: true), findsOneWidget);
      expect(find.textContaining('待听', findRichText: true), findsNothing);
    });

    testWidgets('no record, no metric', (tester) async {
      await pump(tester, _document(record: null));
      expect(find.textContaining('自动补句', findRichText: true), findsNothing);
    });
  });
}
