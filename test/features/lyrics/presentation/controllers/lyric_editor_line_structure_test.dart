import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_line_structure_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
void main() {
  LyricLine line(String text, int startMs, int endMs, String id) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
    id: id,
  );

  LyricEditorDocumentController build(
    List<LyricLine> lines, {
    Map<String, dynamic> metadata = const {},
  }) {
    var now = DateTime.utc(2026, 11, 14, 12);
    final controller = LyricEditorDocumentController(
      clock: () => now = now.add(const Duration(seconds: 5)),
    );
    controller.load(
      LyricDocument(language: 'zh', lines: lines, metadata: metadata),
    );
    return controller;
  }

  group('splitLine', () {
    test('splits at the natural break and selects the second half', () {
      final c = build([
        line('我爱你，你爱我', 0, 6000, 'a'),
        line('下一行', 6000, 8000, 'b'),
      ]);
      final result = c.splitLine(0);

      expect(result.applied, isTrue);
      expect(result.hint, contains('按字数比例'));
      final lines = c.document!.lines;
      expect(lines.map((l) => l.text), ['我爱你', '你爱我', '下一行']);
      expect(lines[0].id, 'a');
      expect(lines[1].id, isNotNull);
      expect(lines[0].endTime, const Duration(milliseconds: 3000));
      expect(lines[1].startTime, const Duration(milliseconds: 3000));
      expect(c.selectedLineIndex, 1);
      expect(c.hasChanges, isTrue);
      // The user decided where the line ends; alignment must keep it.
      expect(c.manuallyEditedLineIds, containsAll(['a', lines[1].id]));
      expect(c.protectedIndices, {0, 1});
    });

    test('uses the cursor offset and a playhead inside the row', () {
      final c = build([line('我爱你你爱我', 0, 6000, 'a')]);
      final result = c.splitLine(
        0,
        textOffset: 2,
        playbackPosition: const Duration(milliseconds: 1500),
      );
      expect(result.hint, contains('暂停位置'));
      expect(c.document!.lines.map((l) => l.text), ['我爱', '你你爱我']);
      expect(c.document!.lines[0].endTime, const Duration(milliseconds: 1500));
    });

    test('is one undo step that also restores the manual marks', () {
      final c = build([line('我爱你，你爱我', 0, 6000, 'a')]);
      c.splitLine(0);
      expect(c.undoLabel, '拆分第 1 行');

      c.undo();
      expect(c.document!.lines.single.text, '我爱你，你爱我');
      expect(c.manuallyEditedLineIds, isEmpty);
      c.redo();
      expect(c.document!.lines, hasLength(2));
    });

    test('a failed split is not an edit and explains why', () {
      final c = build([line('abcdefgh', 0, 6000, 'a')]);
      final result = c.splitLine(0);
      expect(result.applied, isFalse);
      expect(
        result.hint,
        LyricEditorDocumentController.splitFailureMessage(
          LyricLineSplitFailure.noNaturalBreak,
        ),
      );
      expect(c.canUndo, isFalse);
      expect(c.hasChanges, isFalse);
      expect(c.splitLine(5).applied, isFalse);
    });

    test('drops evidence of the split row and shifts later rows', () {
      final c = build(
        [line('我爱你，你爱我', 0, 6000, 'a'), line('下一行', 6000, 8000, 'b')],
        metadata: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 0, 'alternativeText': 'x'},
            {'lineIndex': 1, 'alternativeText': 'y'},
          ],
          LyricIndexedReviewMetadata.candidateCountKey: 2,
        },
      );
      c.splitLine(0);
      final candidates =
          c.document!.metadata[LyricIndexedReviewMetadata.candidatesKey]
              as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['lineIndex'], 2);
      expect((candidates.single as Map)['alternativeText'], 'y');
    });

    test('reports whether the audition must be dropped', () {
      final c = build([line('我爱你，你爱我', 0, 6000, 'a')]);
      expect(c.splitLine(0, auditionTarget: true).clearsAudition, isTrue);
    });
  });

  group('mergeLineWithNext', () {
    test('joins the rows, keeps the first id and follows the selection', () {
      final c = build([
        line('hello', 0, 1000, 'a'),
        line('world', 1000, 2000, 'b'),
        line('again', 3000, 4000, 'c'),
      ]);
      c.updateLine(1, line('world!', 1000, 2000, 'b'));
      c.select(2);

      final result = c.mergeLineWithNext(0);
      expect(result.applied, isTrue);
      expect(result.hint, '已合并第 1–2 行');
      final lines = c.document!.lines;
      expect(lines.map((l) => l.text), ['hello world!', 'again']);
      expect(lines[0].id, 'a');
      expect(lines[0].endTime, const Duration(milliseconds: 2000));
      expect(c.selectedLineIndex, 1);
      expect(c.manuallyEditedLineIds, contains('a'));
      expect(c.manuallyEditedLineIds, isNot(contains('b')));
    });

    test('a selected second row moves onto the merged row', () {
      final c = build([line('一', 0, 1000, 'a'), line('二', 1000, 2000, 'b')]);
      c.select(1);
      c.mergeLineWithNext(0);
      expect(c.selectedLineIndex, 0);
      expect(c.document!.lines.single.text, '一二');
    });

    test('the last row has nothing to merge with', () {
      final c = build([line('一', 0, 1000, 'a')]);
      final result = c.mergeLineWithNext(0);
      expect(result.applied, isFalse);
      expect(result.hint, contains('最后一行'));
      expect(c.canUndo, isFalse);
    });

    test('drops evidence of both rows and shifts later rows up', () {
      final c = build(
        [
          line('一', 0, 1000, 'a'),
          line('二', 1000, 2000, 'b'),
          line('三', 2000, 3000, 'c'),
        ],
        metadata: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 0, 'alternativeText': 'x'},
            {'lineIndex': 1, 'alternativeText': 'y'},
            {'lineIndex': 2, 'alternativeText': 'z'},
          ],
          LyricIndexedReviewMetadata.candidateCountKey: 3,
          LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [1, 2],
        },
      );
      c.mergeLineWithNext(0);
      final metadata = c.document!.metadata;
      final candidates =
          metadata[LyricIndexedReviewMetadata.candidatesKey] as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['lineIndex'], 1);
      expect(metadata[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey], [
        1,
      ]);
    });

    test('undo restores both rows', () {
      final c = build([line('一', 0, 1000, 'a'), line('二', 1000, 2000, 'b')]);
      c.mergeLineWithNext(0);
      c.undo();
      expect(c.document!.lines.map((l) => l.text), ['一', '二']);
    });
  });

  group('LyricIndexedReviewMetadata structural remaps', () {
    test('afterRowSplit drops the split row and shifts later rows down', () {
      final result = LyricIndexedReviewMetadata.afterRowSplit({
        LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [0, 1, 3],
      }, 1);
      expect(result[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey], [
        0,
        4,
      ]);
    });

    test('afterRowsMerged drops both rows and shifts later rows up', () {
      final result = LyricIndexedReviewMetadata.afterRowsMerged({
        LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [0, 1, 2, 4],
      }, 1);
      expect(result[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey], [
        0,
        3,
      ]);
    });
  });
}
