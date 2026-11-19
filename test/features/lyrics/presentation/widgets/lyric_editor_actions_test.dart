import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_actions.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  group('LyricEditHistory', () {
    final calls = <String>[];
    void undo() => calls.add('undo');
    void redo() => calls.add('redo');

    setUp(calls.clear);

    test('nothing to undo or redo disables both and hides the labels', () {
      final history = LyricEditHistory(
        onUndo: undo,
        onRedo: redo,
        undoLabel: '编辑歌词',
        redoLabel: '删除行',
      );

      expect(history.undoOrNull, isNull);
      expect(history.redoOrNull, isNull);
      expect(history.availableUndoLabel, isNull);
      expect(history.availableRedoLabel, isNull);
    });

    test('an available action keeps its callback and label', () {
      final history = LyricEditHistory(
        onUndo: undo,
        onRedo: redo,
        canUndo: true,
        undoLabel: '编辑歌词',
        redoLabel: '删除行',
      );

      history.undoOrNull!();
      expect(calls, ['undo']);
      expect(history.availableUndoLabel, '编辑歌词');
      expect(history.redoOrNull, isNull);
      expect(history.availableRedoLabel, isNull);
    });

    test('keyboard shortcuts can still reach the raw callbacks', () {
      final history = LyricEditHistory(onUndo: undo, onRedo: redo);

      history.onUndo();
      history.onRedo();
      expect(calls, ['undo', 'redo']);
    });
  });

  group('LyricProofreadActions', () {
    test('none offers no tool', () {
      const none = LyricProofreadActions.none;

      expect(none.onReferenceAlignment, isNull);
      expect(none.onReferenceProofread, isNull);
      expect(none.onProofreadV2, isNull);
      expect(none.onUndoReferenceAlignment, isNull);
      expect(none.onViewAlignmentComparison, isNull);
      expect(none.onRestoreAlignment, isNull);
      expect(none.onUnifyChineseScript, isNull);
      expect(none.onBatchTextTool, isNull);
    });

    test('batch tools receive the tool that was picked', () {
      final opened = <LyricBatchTextTool>[];
      final actions = LyricProofreadActions(onBatchTextTool: opened.add);

      actions.onBatchTextTool!(LyricBatchTextTool.findReplace);
      expect(opened, [LyricBatchTextTool.findReplace]);
    });
  });

  test('LyricLineEditActions passes row edits through', () {
    final log = <String>[];
    final actions = LyricLineEditActions(
      onAddLine: () => log.add('add'),
      onInsertAtPlayback: () => log.add('insert'),
      onUpdateLine: (index, line) => log.add('update $index ${line.text}'),
      onDeleteLine: (index) => log.add('delete $index'),
      onUpdateOffset: (offset) => log.add('offset ${offset.inMilliseconds}'),
      onSetStartFromPlayback: (index) => log.add('start $index'),
      onSetEndFromPlayback: (index) => log.add('end $index'),
    );

    actions.onAddLine();
    actions.onInsertAtPlayback();
    actions.onUpdateLine(
      2,
      const LyricLine(
        text: '新的歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
      ),
    );
    actions.onDeleteLine(3);
    actions.onUpdateOffset(const Duration(milliseconds: 150));
    actions.onSetStartFromPlayback(4);
    actions.onSetEndFromPlayback(5);

    expect(log, [
      'add',
      'insert',
      'update 2 新的歌词',
      'delete 3',
      'offset 150',
      'start 4',
      'end 5',
    ]);
    // Splitting and merging are optional, as on a read-only document.
    expect(actions.onSplitLine, isNull);
    expect(actions.onMergeLineWithNext, isNull);
  });

  test('LyricAuditionControls defaults to a silent, unlooped row', () {
    final previewed = <int>[];
    final loops = <bool>[];
    final audition = LyricAuditionControls(
      onPreviewLine: previewed.add,
      onLoopCurrentLineChanged: loops.add,
    );

    expect(audition.activeLineIndex, isNull);
    expect(audition.playing, isFalse);
    expect(audition.loopCurrentLine, isFalse);
    audition.onPreviewLine(7);
    audition.onLoopCurrentLineChanged(true);
    expect(previewed, [7]);
    expect(loops, [true]);
  });
}
