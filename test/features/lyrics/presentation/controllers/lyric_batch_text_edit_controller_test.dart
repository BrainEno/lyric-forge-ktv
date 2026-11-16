import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line(String text, String id) => LyricLine(
    text: text,
    startTime: Duration.zero,
    endTime: const Duration(seconds: 1),
    id: id,
  );

  LyricDocument document(List<LyricLine> lines) =>
      LyricDocument(language: 'zh', lines: lines);

  LyricEditorDocumentController build() {
    var now = DateTime.utc(2026, 11, 14, 12);
    final controller = LyricEditorDocumentController(
      clock: () => now = now.add(const Duration(seconds: 5)),
    );
    controller.load(document([line('我碍你', 'a'), line('你好', 'b')]));
    return controller;
  }

  test('a batch text edit protects the rows the user chose', () {
    final controller = build();
    controller.replaceDocument(
      document([line('我爱你', 'a'), line('你好', 'b')]),
      label: '批量查找替换',
      selectedLineIndex: 0,
      keepBatchSnapshot: true,
      markManuallyEditedLineIds: {'a'},
    );

    expect(controller.manuallyEditedLineIds, {'a'});
    expect(controller.protectedIndices, {0});
    expect(controller.alignmentSnapshot, isNotNull);
    expect(controller.documentForSave().metadata['manuallyEditedLineIds'], [
      'a',
    ]);
  });

  test('undoing the batch drops the protection it added', () {
    final controller = build();
    controller.replaceDocument(
      document([line('我爱你', 'a'), line('你好', 'b')]),
      label: '批量查找替换',
      selectedLineIndex: 0,
      keepBatchSnapshot: true,
      markManuallyEditedLineIds: {'a'},
    );

    expect(controller.undoBatchChange().applied, isTrue);
    expect(controller.manuallyEditedLineIds, isEmpty);
    expect(controller.document!.lines.first.text, '我碍你');
  });

  test('history undo restores the previous protection too', () {
    final controller = build();
    controller.replaceDocument(
      document([line('我爱你', 'a'), line('你好', 'b')]),
      label: '批量查找替换',
      selectedLineIndex: 0,
      markManuallyEditedLineIds: {'a'},
    );
    expect(controller.undo().applied, isTrue);
    expect(controller.manuallyEditedLineIds, isEmpty);
    expect(controller.redo().applied, isTrue);
    expect(controller.manuallyEditedLineIds, {'a'});
  });

  test('mechanical batch edits do not protect rows', () {
    final controller = build();
    controller.replaceDocument(
      document([line('我碍你', 'a'), line('你好', 'b')]),
      label: '清理识别文本',
      selectedLineIndex: 0,
      keepBatchSnapshot: true,
    );
    expect(controller.manuallyEditedLineIds, isEmpty);
  });
}
