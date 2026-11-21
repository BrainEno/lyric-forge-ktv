import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_actions.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_vocal_check_request.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _s(double value) => Duration(milliseconds: (value * 1000).round());

LyricLine _line(String text, double start, double end) =>
    LyricLine(text: text, startTime: _s(start), endTime: _s(end));

LyricVocalCheckSpan _span(double start, double end) =>
    LyricVocalCheckSpan(_s(start), _s(end));

LyricVocalCheckRemovedLine _removed(String text, double start, double end) =>
    LyricVocalCheckRemovedLine(text: text, start: _s(start), end: _s(end));

LyricDocument _document(
  List<LyricLine> lines, {
  LyricVocalCheckRecord? record,
}) => LyricDocument(
  language: 'zh',
  lines: lines,
  metadata: {
    'primaryEngine': 'qwen3-asr-1.7b',
    if (record != null) LyricVocalCheckRecord.metadataKey: record.toJson(),
  },
);

RecognitionReviewSummary _summary(LyricDocument document) =>
    RecognitionReviewSummary.fromDocument(
      document,
      LyricReviewQueue.build(document),
    );

final _record = LyricVocalCheckRecord(
  removedLines: [_removed('字幕由某某提供', 1, 5), _removed('间奏里编出来的', 60, 64)],
  retimedLines: 1,
  uncoveredSpans: [_span(75, 79), _span(120, 124)],
);

final _requests = <LyricVocalCheckRequest>[];

Future<void> _pump(
  WidgetTester tester,
  LyricDocument document, {
  bool actionable = true,
}) async {
  _requests.clear();
  tester.view.physicalSize = const Size(1280, 900);
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
              onVocalCheckAction: actionable ? _requests.add : null,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('card buttons', () {
    testWidgets('one button per open stretch recognises it', (tester) async {
      await _pump(tester, _document([_line('第一句', 10, 15)], record: _record));
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_gaps')),
        findsOneWidget,
      );
      expect(find.text('识别 1:15.0'), findsOneWidget);
      expect(find.text('识别 2:00.0'), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_vocal_gap_all')), findsNothing);
      expect(find.textContaining('点下面的时间直接识别并插入'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lyric_vocal_gap_1')));
      await tester.pump();
      final request = _requests.single as LyricVocalGapRequest;
      expect(request.span, _span(120, 124));
    });

    testWidgets('more stretches than listed get a walk-through button', (
      tester,
    ) async {
      final record = LyricVocalCheckRecord(
        uncoveredSpans: [
          for (var index = 0; index < 5; index++)
            _span(30.0 + index * 10, 33.0 + index * 10),
        ],
      );
      await _pump(tester, _document([_line('第一句', 10, 15)], record: record));
      expect(find.byKey(const ValueKey('lyric_vocal_gap_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_vocal_gap_3')), findsNothing);
      expect(find.text('逐处识别（共 5 处）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lyric_vocal_gap_all')));
      await tester.pump();
      expect((_requests.single as LyricVocalGapRequest).span, isNull);
    });

    testWidgets('closed stretches get no button', (tester) async {
      await _pump(
        tester,
        _document([
          _line('第一句', 10, 15),
          _line('补写', 75, 79),
          _line('又补写', 120, 124),
        ], record: _record),
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_gaps')),
        findsNothing,
      );
      // The removed rows can still be restored.
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_removed')),
        findsOneWidget,
      );
    });

    testWidgets('removed rows can be restored all at once or reviewed', (
      tester,
    ) async {
      await _pump(tester, _document([_line('第一句', 10, 15)], record: _record));
      expect(find.text('人声检查删除了 2 行没人唱的歌词'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lyric_vocal_restore_all')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('lyric_vocal_restore_review')),
      );
      await tester.pump();
      expect(_requests, hasLength(2));
      expect((_requests.first as LyricRestoreRemovedRequest).all, isTrue);
      expect((_requests.last as LyricRestoreRemovedRequest).all, isFalse);
    });

    testWidgets('no removed rows, no restore buttons', (tester) async {
      await _pump(
        tester,
        _document([
          _line('第一句', 10, 15),
        ], record: LyricVocalCheckRecord(uncoveredSpans: [_span(75, 79)])),
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_removed')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('lyric_vocal_gap_0')), findsOneWidget);
    });

    testWidgets('without a handler the card keeps the manual hint', (
      tester,
    ) async {
      await _pump(
        tester,
        _document([_line('第一句', 10, 15)], record: _record),
        actionable: false,
      );
      expect(find.byKey(const ValueKey('lyric_vocal_gap_0')), findsNothing);
      expect(
        find.byKey(const ValueKey('lyric_vocal_restore_all')),
        findsNothing,
      );
      expect(find.textContaining('重新识别这一段'), findsOneWidget);
    });

    testWidgets('no record, no buttons', (tester) async {
      await _pump(tester, _document([_line('第一句', 10, 15)]));
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_gaps')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_removed')),
        findsNothing,
      );
    });
  });

  group('summary text', () {
    test('the stretch hint points at the buttons when there are any', () {
      final summary = _summary(
        _document([_line('第一句', 10, 15)], record: _record),
      );
      expect(
        LyricRecognitionSummaryCard.vocalSpansLine(summary, actionable: true),
        '有人声但没有歌词：1:15.0–1:19.0、2:00.0–2:04.0。点下面的时间直接识别并插入，或试听后补写',
      );
      expect(
        LyricRecognitionSummaryCard.vocalSpansLine(summary),
        contains('重新识别这一段'),
      );
    });

    test('restored rows and dismissed stretches are counted', () {
      final record = _record.withRestored({0}).withDismissed(_span(120, 124));
      final lines = LyricRecognitionSummaryCard.vocalCheckLines(record);
      expect(lines, contains('已恢复 1 行被删除的歌词'));
      expect(lines, contains('已标记 1 处有人声的地方没有歌词'));
      expect(lines.first, contains('删除了 1 行'));
    });

    test('restoring everything does not claim nothing was found', () {
      const record = LyricVocalCheckRecord(restoredLines: 2);
      final lines = LyricRecognitionSummaryCard.vocalCheckLines(record);
      expect(lines, ['已恢复 2 行被删除的歌词']);
    });
  });

  group('editor actions', () {
    LyricProofreadActions actionsFor({
      required bool hasLines,
      ValueChanged<LyricVocalCheckRequest>? vocalCheckAction,
    }) => LyricProofreadActions.forDocument(
      hasLines: hasLines,
      referenceAlignment: () {},
      referenceProofread: () {},
      smartProofread: () {},
      undoAlignment: () {},
      viewComparison: () {},
      restoreAlignment: () {},
      unifyChineseScript: () {},
      batchTextTool: (_) {},
      vocalCheckAction: vocalCheckAction,
    );

    test('the follow-ups need a document with rows', () {
      void handler(LyricVocalCheckRequest _) {}
      expect(
        actionsFor(
          hasLines: true,
          vocalCheckAction: handler,
        ).onVocalCheckAction,
        isNotNull,
      );
      expect(
        actionsFor(
          hasLines: false,
          vocalCheckAction: handler,
        ).onVocalCheckAction,
        isNull,
      );
      expect(actionsFor(hasLines: true).onVocalCheckAction, isNull);
      expect(LyricProofreadActions.none.onVocalCheckAction, isNull);
    });

    test('the batch tool list has the two follow-ups', () {
      expect(
        LyricBatchTextTool.values,
        containsAll([
          LyricBatchTextTool.vocalGapRecognition,
          LyricBatchTextTool.restoreRemovedLines,
        ]),
      );
    });
  });
}
