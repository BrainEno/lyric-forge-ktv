import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument _document(int count, {bool ids = true}) => LyricDocument(
  language: 'zh',
  lines: [
    for (var index = 0; index < count; index++)
      LyricLine(
        id: ids ? 'l$index' : null,
        text: '第$index句',
        startTime: Duration(seconds: index * 4 + 1),
        endTime: Duration(seconds: index * 4 + 3),
      ),
  ],
);

List<String> _texts(LyricEditorDocumentController controller) => [
  for (final line in controller.document!.lines) line.text,
];

void main() {
  late LyricEditorDocumentController controller;
  var notified = 0;

  setUp(() {
    controller = LyricEditorDocumentController(
      clock: () => DateTime.utc(2026, 12, 29),
    )..load(_document(6));
    notified = 0;
    controller.addListener(() => notified++);
  });

  tearDown(() => controller.dispose());

  final all = List<int>.generate(6, (index) => index);

  group('choosing rows', () {
    test('starts off, and the 多选 button turns it on with nothing chosen', () {
      expect(controller.batchMode, isFalse);
      controller.startBatch();
      expect(controller.batchMode, isTrue);
      expect(controller.batchSelection, isEmpty);
      expect(notified, 1);
    });

    test('a tap in batch mode chooses a row and a second tap drops it', () {
      controller
        ..startBatch()
        ..toggleBatchLine(3)
        ..toggleBatchLine(1);
      expect(controller.batchSelection, [1, 3]);
      controller.toggleBatchLine(3);
      expect(controller.batchSelection, [1]);
      expect(controller.batchMode, isTrue, reason: 'Esc or ✕ leaves');
    });

    test('Ctrl+click also chooses the row that was selected before', () {
      controller.select(2);
      controller.toggleBatchLine(4, includeCurrent: true);
      expect(controller.batchSelection, [2, 4]);
      expect(controller.selectedLineIndex, 4);
    });

    test('Shift chooses from the anchor through the shown order', () {
      controller.select(1);
      controller.selectBatchRange(4, all);
      expect(controller.batchSelection, [1, 2, 3, 4]);
      // The anchor stays where the range began.
      controller.selectBatchRange(0, all);
      expect(controller.batchSelection, [0, 1]);
    });

    test('a range skips rows the filter hides', () {
      controller.select(0);
      controller.selectBatchRange(5, [0, 2, 5]);
      expect(controller.batchSelection, [0, 2, 5]);
    });

    test('select all and end', () {
      controller.selectAllBatch([1, 2]);
      expect(controller.batchSelection, [1, 2]);
      controller.endBatch();
      expect(controller.batchMode, isFalse);
      expect(controller.batchSelection, isEmpty);
    });

    test('the choice follows the rows through an edit above them', () {
      controller.selectAllBatch([3, 4]);
      controller.deleteLine(0);
      expect(controller.batchSelection, [2, 3]);
    });

    test('rows without an id get one so they can be chosen', () {
      controller.load(_document(3, ids: false));
      controller.toggleBatchLine(1);
      expect(controller.batchSelection, [1]);
      expect(controller.hasChanges, isFalse);
      expect(controller.canUndo, isFalse);
    });

    test('loading another document forgets the choice', () {
      controller.selectAllBatch([0, 1]);
      controller.load(_document(2));
      expect(controller.batchMode, isFalse);
      expect(controller.batchSelection, isEmpty);
    });

    test('choosing is not an edit', () {
      final revision = controller.documentRevision;
      controller
        ..toggleBatchLine(1)
        ..selectBatchRange(3, all);
      expect(controller.documentRevision, revision);
      expect(controller.hasChanges, isFalse);
    });
  });

  group('batch edits', () {
    const decisions = LyricReviewDecisionService();

    test('marks rows reviewed as one undo step and leaves batch mode', () {
      controller.selectAllBatch([1, 3]);
      final result = controller.setLinesReviewed([1, 3], reviewed: true);
      expect(result.applied, isTrue);
      expect(result.hint, '已将 2 行标记为已复核');
      expect(decisions.reviewedIndices(controller.document!), {1, 3});
      expect(controller.batchMode, isFalse);

      controller.undo();
      expect(decisions.reviewedIndices(controller.document!), isEmpty);
    });

    test('says so when every row already has the mark', () {
      controller.setLinesReviewed([1], reviewed: true);
      final result = controller.setLinesReviewed([1], reviewed: true);
      expect(result.applied, isFalse);
      expect(result.hint, '选中的行都已经复核过了');
    });

    test('clears marks from only the rows that had one', () {
      controller.setLinesReviewed([1, 2], reviewed: true);
      final result = controller.setLinesReviewed([1, 4], reviewed: false);
      expect(result.hint, '已取消 1 行的复核标记');
      expect(decisions.reviewedIndices(controller.document!), {2});
    });

    test('deletes rows in one step; undo brings them all back', () {
      controller.select(4);
      controller.selectAllBatch([1, 2]);
      final result = controller.deleteLines([1, 2]);
      expect(result.hint, '已删除 2 行');
      expect(_texts(controller), ['第0句', '第3句', '第4句', '第5句']);
      expect(controller.selectedLineIndex, 2, reason: 'still 第4句');
      expect(controller.batchMode, isFalse);
      expect(controller.undoLabel, '删除 2 行');

      controller.undo();
      expect(controller.document!.lines, hasLength(6));
    });

    test('deleting the selected row selects the one in its place', () {
      controller.select(2);
      controller.deleteLines([2, 3]);
      expect(controller.selectedLineIndex, 2);
      expect(controller.document!.lines[2].text, '第4句');
    });

    test('deleting every row clears the selection', () {
      controller.deleteLines(all);
      expect(controller.document!.lines, isEmpty);
      expect(controller.selectedLineIndex, isNull);
    });

    test('merges neighbours into one hand-edited row', () {
      controller.select(4);
      final result = controller.mergeLines([1, 2, 3]);
      expect(result.hint, '已把第 2–4 行合并成一行');
      expect(_texts(controller), ['第0句', '第1句第2句第3句', '第4句', '第5句']);
      expect(controller.manuallyEditedLineIds, {'l1'});
      expect(controller.selectedLineIndex, 2);
      controller.undo();
      expect(controller.document!.lines, hasLength(6));
      expect(controller.manuallyEditedLineIds, isEmpty);
    });

    test('will not merge rows with a gap', () {
      final result = controller.mergeLines([1, 3]);
      expect(result.applied, isFalse);
      expect(result.hint, '只能合并相邻的行，请选连续的几行');
      expect(controller.canUndo, isFalse);
    });

    test('shifts the chosen rows and keeps them chosen', () {
      controller.selectAllBatch([0, 2]);
      final result = controller.shiftLines([
        0,
        2,
      ], const Duration(milliseconds: -500));
      expect(result.hint, '已把 2 行的时间提前 0.50 秒');
      final lines = controller.document!.lines;
      expect(lines[0].startTime, const Duration(milliseconds: 500));
      expect(lines[1].startTime, const Duration(seconds: 5));
      expect(lines[2].startTime, const Duration(milliseconds: 8500));
      expect(controller.batchSelection, [0, 2]);
      expect(controller.batchMode, isTrue);
      expect(controller.undoLabel, '平移 2 行的时间');
    });

    test('a shift that changes nothing is not an edit', () {
      final result = controller.shiftLines([0], Duration.zero);
      expect(result.applied, isFalse);
      expect(controller.canUndo, isFalse);
    });

    test('the shift message notes rows held at an edge', () {
      expect(
        lyricBatchShiftMessage(3, const Duration(seconds: 1), 1),
        '已把 3 行的时间推后 1.00 秒（1 行已到开头或结尾，停在边界）',
      );
    });
  });
}
