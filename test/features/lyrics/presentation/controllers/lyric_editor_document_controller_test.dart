import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line(
    String text, {
    int startMs = 0,
    int endMs = 1000,
    String? id,
  }) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
    id: id,
  );

  LyricDocument document(
    List<LyricLine> lines, {
    Map<String, dynamic> metadata = const {},
    Duration? globalOffset,
  }) => LyricDocument(
    language: 'zh',
    lines: lines,
    metadata: metadata,
    globalOffset: globalOffset,
  );

  /// A controller whose clock only moves when the test says so, so the undo
  /// merge window is deterministic instead of wall-clock dependent.
  ({LyricEditorDocumentController controller, void Function() advance}) build({
    LyricDocument? loaded,
  }) {
    var now = DateTime.utc(2026, 11, 3, 12);
    final controller = LyricEditorDocumentController(clock: () => now);
    if (loaded != null) controller.load(loaded);
    return (
      controller: controller,
      advance: () => now = now.add(const Duration(seconds: 5)),
    );
  }

  test('document revision tracks mutations, not selection or save bookkeeping', () {
    final c = build(loaded: document([line('a', id: 'a')])).controller;
    var revision = c.documentRevision;
    void changed() {
      expect(c.documentRevision, greaterThan(revision));
      revision = c.documentRevision;
    }

    c.select(null);
    c.markSaved();
    c.updateLine(3, line('invalid'));
    expect(c.documentRevision, revision);
    c.updateLine(0, line('edited', id: 'a'));
    changed();
    c.markSaved();
    expect(c.documentRevision, revision);
    c.undo();
    changed();
    c.redo();
    changed();
    c.setLineReviewed(0, reviewed: true);
    changed();
    c.replaceDocument(c.document!, label: 'batch', selectedLineIndex: 0, keepBatchSnapshot: true);
    changed();
    c.undoBatchChange();
    changed();
    c.restoreDocument(c.document!, label: 'restore');
    changed();
    c.load(c.document!);
    changed();
    c.addLine();
    changed();
    c.insertLineAt(const Duration(seconds: 3));
    changed();
    c.deleteLine(0);
    changed();
    c.updateGlobalOffset(const Duration(milliseconds: 50));
    changed();
    c.dispose();
  });

  group('load', () {
    test('assigns ids, restores persisted marks and selects the first row', () {
      final persisted = const LyricManualEditMarkerService().persist(
        document([line('a', id: 'a'), line('b', id: 'b')]),
        {'b'},
      );
      final entry = build(
        loaded: document([
          line('a', id: 'a'),
          line('b', id: 'b'),
        ]).copyWith(metadata: persisted),
      );

      expect(entry.controller.document!.lines.map((row) => row.id), ['a', 'b']);
      expect(entry.controller.selectedLineIndex, 0);
      expect(entry.controller.manuallyEditedLineIds, {'b'});
      expect(entry.controller.protectedIndices, {1});
      expect(entry.controller.hasChanges, isFalse);
    });

    test('fills in missing line ids so later edits can follow a row', () {
      final entry = build(loaded: document([line('no id')]));

      expect(entry.controller.document!.lines.single.id, isNotNull);
    });

    test('an empty document has no selection', () {
      final entry = build(loaded: document(const []));

      expect(entry.controller.selectedLineIndex, isNull);
    });

    test('loading clears the undo history', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('a edited', id: 'a'));
      expect(entry.controller.canUndo, isTrue);

      entry.controller.load(document([line('x', id: 'x')]));

      expect(entry.controller.canUndo, isFalse);
      expect(entry.controller.canRedo, isFalse);
    });
  });

  group('notifications', () {
    test('notifies on observable changes but not on no-op operations', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      var notifications = 0;
      entry.controller.addListener(() => notifications++);

      entry.controller.select(0);
      expect(notifications, 0);
      entry.controller.select(null);
      expect(notifications, 1);
      entry.controller.select(null);
      expect(notifications, 1);

      entry.controller.updateLine(0, line('edited', id: 'a'));
      expect(notifications, 2);
      entry.controller.updateLine(3, line('missing'));
      expect(notifications, 2);

      entry.controller.dispose();
    });

    test('loading publishes the new document outside the caller', () {
      final entry = build();
      var notifications = 0;
      entry.controller.addListener(() => notifications++);

      entry.controller.load(document([line('a', id: 'a')]));

      expect(notifications, 1);
      expect(entry.controller.document!.lines.single.text, 'a');
      entry.controller.dispose();
    });
  });

  group('undo and redo', () {
    test('undo restores the document and the selection that produced it', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.select(1);
      entry.controller.updateLine(
        1,
        line('b edited', startMs: 1000, endMs: 2000, id: 'b'),
      );

      final undone = entry.controller.undo();

      expect(undone.applied, isTrue);
      expect(undone.hint, '已撤销：修改第 2 行');
      expect(undone.clearsAudition, isTrue);
      expect(entry.controller.document!.lines[1].text, 'b');
      expect(entry.controller.selectedLineIndex, 1);
      expect(entry.controller.canRedo, isTrue);
      expect(entry.controller.hasChanges, isFalse);
    });

    test('redo reapplies the edit and restores its protected mark', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('a edited', id: 'a'));
      entry.controller.undo();

      final redone = entry.controller.redo();

      expect(redone.applied, isTrue);
      expect(redone.hint, '已重做：修改第 1 行');
      expect(entry.controller.document!.lines.single.text, 'a edited');
      expect(entry.controller.manuallyEditedLineIds, {'a'});
      expect(entry.controller.protectedIndices, {0});
      expect(entry.controller.hasChanges, isTrue);
    });

    test(
      'undoing back to a clean baseline clears its manual mark and dirtiness',
      () {
        final entry = build(loaded: document([line('a', id: 'a')]));
        entry.controller.updateLine(0, line('a edited', id: 'a'));

        entry.controller.undo();

        expect(entry.controller.document!.lines.single.text, 'a');
        expect(entry.controller.manuallyEditedLineIds, isEmpty);
        expect(entry.controller.protectedIndices, isEmpty);
        expect(entry.controller.hasChanges, isFalse);
        final saved = entry.controller.documentForSave();
        expect(
          saved.metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey],
          isEmpty,
        );
        final reopened = build(loaded: saved);
        expect(reopened.controller.manuallyEditedLineIds, isEmpty);
        expect(reopened.controller.protectedIndices, isEmpty);
      },
    );

    test('step-by-step undo walks marks and dirtiness back to clean', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(0, line('a1', id: 'a'));
      entry.controller.updateLine(1, line('b1', id: 'b'));
      expect(entry.controller.manuallyEditedLineIds, {'a', 'b'});

      entry.controller.undo();
      expect(entry.controller.document!.lines[1].text, 'b');
      expect(entry.controller.manuallyEditedLineIds, {'a'});
      expect(entry.controller.hasChanges, isTrue);

      entry.controller.undo();
      expect(entry.controller.document!.lines[0].text, 'a');
      expect(entry.controller.manuallyEditedLineIds, isEmpty);
      expect(entry.controller.hasChanges, isFalse);
    });

    test('a typing burst is one step for marks and dirtiness too', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('ab', id: 'a'));
      entry.controller.updateLine(0, line('abc', id: 'a'));
      expect(entry.controller.history.undoDepth, 1);

      entry.controller.undo();

      expect(entry.controller.document!.lines.single.text, 'a');
      expect(entry.controller.manuallyEditedLineIds, isEmpty);
      expect(entry.controller.hasChanges, isFalse);
    });

    test('undoing a delete restores the deleted row manual edit mark', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(1, line('b fixed', id: 'b'));
      entry.controller.deleteLine(1);
      expect(entry.controller.manuallyEditedLineIds, isEmpty);

      entry.controller.undo();

      expect(entry.controller.document!.lines, hasLength(2));
      expect(entry.controller.manuallyEditedLineIds, {'b'});
      expect(entry.controller.protectedIndices, {1});
      expect(entry.controller.hasChanges, isTrue);
    });

    test(
      'undo after saving is dirty, while redo returns to the saved state',
      () {
        final entry = build(loaded: document([line('a', id: 'a')]));
        entry.controller.updateLine(0, line('a edited', id: 'a'));
        entry.controller.markSaved();
        expect(entry.controller.hasChanges, isFalse);

        entry.controller.undo();
        expect(entry.controller.document!.lines.single.text, 'a');
        expect(entry.controller.hasChanges, isTrue);
        expect(entry.controller.manuallyEditedLineIds, isEmpty);

        entry.controller.redo();
        expect(entry.controller.document!.lines.single.text, 'a edited');
        expect(entry.controller.manuallyEditedLineIds, {'a'});
        expect(entry.controller.hasChanges, isFalse);
      },
    );

    test(
      'multiple undo and redo steps stay dirty relative to the saved baseline',
      () {
        final entry = build(
          loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
        );
        entry.controller.updateLine(0, line('a1', id: 'a'));
        entry.controller.updateLine(1, line('b1', id: 'b'));
        entry.controller.markSaved();
        expect(entry.controller.hasChanges, isFalse);

        entry.controller.undo();
        expect(entry.controller.document!.lines.map((row) => row.text), [
          'a1',
          'b',
        ]);
        expect(entry.controller.manuallyEditedLineIds, {'a'});
        expect(entry.controller.hasChanges, isTrue);

        entry.controller.undo();
        expect(entry.controller.document!.lines.map((row) => row.text), [
          'a',
          'b',
        ]);
        expect(entry.controller.manuallyEditedLineIds, isEmpty);
        expect(entry.controller.hasChanges, isTrue);

        entry.controller.redo();
        expect(entry.controller.manuallyEditedLineIds, {'a'});
        expect(entry.controller.hasChanges, isTrue);

        entry.controller.redo();
        expect(entry.controller.manuallyEditedLineIds, {'a', 'b'});
        expect(entry.controller.hasChanges, isFalse);
      },
    );

    test('an empty history answers with a message instead of a change', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      final undone = entry.controller.undo();
      final redone = entry.controller.redo();

      expect(undone.applied, isFalse);
      expect(undone.hint, '没有可撤销的修改');
      expect(redone.applied, isFalse);
      expect(redone.hint, '没有可重做的修改');
    });

    test('a new edit drops the redo branch', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('one', id: 'a'));
      entry.controller.undo();
      expect(entry.controller.canRedo, isTrue);

      entry.controller.updateLine(0, line('two', id: 'a'));

      expect(entry.controller.canRedo, isFalse);
    });

    test('undo never restores a selection that no longer exists', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.select(1);
      entry.controller.deleteLine(1);
      entry.controller.select(1);

      entry.controller.undo();

      expect(entry.controller.document!.lines, hasLength(2));
      expect(entry.controller.selectedLineIndex, 1);
    });
  });

  group('updateLine', () {
    test('a text change marks the row as manually edited', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      entry.controller.updateLine(0, line('a fixed', id: 'a'));

      expect(entry.controller.manuallyEditedLineIds, {'a'});
      expect(entry.controller.protectedIndices, {0});
      expect(entry.controller.hasChanges, isTrue);
    });

    test('a timing-only change leaves the row unprotected', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('a fixed', id: 'a'));
      final before = Set<String>.from(entry.controller.manuallyEditedLineIds);

      entry.controller.updateLine(0, line('a fixed', startMs: 500, id: 'a'));

      expect(entry.controller.manuallyEditedLineIds, before);
    });

    test('edits to one row inside the merge window are a single undo step', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('ab', id: 'a'));
      entry.controller.updateLine(0, line('abc', id: 'a'));

      expect(entry.controller.history.undoDepth, 1);
      entry.controller.undo();
      expect(entry.controller.document!.lines.single.text, 'a');
    });

    test('edits to different rows are separate undo steps', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(0, line('a1', id: 'a'));
      entry.controller.updateLine(
        1,
        line('b1', startMs: 1000, endMs: 2000, id: 'b'),
      );

      expect(entry.controller.history.undoDepth, 2);
    });

    test('an edit outside the merge window starts a new step', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('ab', id: 'a'));
      entry.advance();
      entry.controller.updateLine(0, line('abc', id: 'a'));

      expect(entry.controller.history.undoDepth, 2);
    });

    test('an out-of-range row is a no-op', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      expect(entry.controller.updateLine(3, line('x')).applied, isFalse);
      expect(entry.controller.updateLine(-1, line('x')).applied, isFalse);
      expect(entry.controller.canUndo, isFalse);
    });

    test('only a timing change to the auditioned row drops the audition', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );

      expect(
        entry.controller
            .updateLine(0, line('a2', id: 'a'), auditionTarget: true)
            .clearsAudition,
        isFalse,
      );
      expect(
        entry.controller
            .updateLine(
              0,
              line('a2', startMs: 10, id: 'a'),
              auditionTarget: true,
            )
            .clearsAudition,
        isTrue,
      );
      expect(
        entry.controller
            .updateLine(
              1,
              line('b', startMs: 1000, endMs: 2000, id: 'b'),
              auditionTarget: false,
            )
            .clearsAudition,
        isFalse,
      );
    });
  });

  group('deleteLine', () {
    test(
      'deleting the selected last row clamps the selection to the new end',
      () {
        final entry = build(
          loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
        );
        entry.controller.select(1);

        entry.controller.deleteLine(1);

        expect(entry.controller.document!.lines.map((row) => row.text), ['a']);
        expect(entry.controller.selectedLineIndex, 0);
      },
    );

    test('deleting a row above the selection keeps the same row selected', () {
      final entry = build(
        loaded: document([
          line('a', id: 'a'),
          line('b', id: 'b'),
          line('c', id: 'c'),
        ]),
      );
      entry.controller.select(2);

      entry.controller.deleteLine(0);

      expect(entry.controller.document!.lines.map((row) => row.text), [
        'b',
        'c',
      ]);
      expect(entry.controller.selectedLineIndex, 1);
      expect(entry.controller.document!.lines[1].id, 'c');
    });

    test('deleting the last row clears the selection', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.select(0);

      entry.controller.deleteLine(0);

      expect(entry.controller.selectedLineIndex, isNull);
      expect(entry.controller.document!.lines, isEmpty);
    });

    test('the deleted row loses its manual edit mark', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(
        1,
        line('b fixed', startMs: 1000, endMs: 2000, id: 'b'),
      );
      expect(entry.controller.manuallyEditedLineIds, {'b'});

      entry.controller.deleteLine(1);

      expect(entry.controller.manuallyEditedLineIds, isEmpty);
    });

    test('row-indexed fallback metadata is dropped', () {
      final entry = build(
        loaded: document(
          [line('a', id: 'a'), line('b', id: 'b')],
          metadata: const {
            'fallbackCandidates': {'0': 'x'},
            'fallbackCandidateCount': 1,
            'fallbackAppliedCount': 1,
            'untouched': 'kept',
          },
        ),
      );

      entry.controller.deleteLine(0);

      expect(entry.controller.document!.metadata, {'untouched': 'kept'});
    });

    test('deleting the auditioned row drops the audition', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );

      expect(
        entry.controller.deleteLine(0, auditionTarget: true).clearsAudition,
        isTrue,
      );
      expect(
        entry.controller.deleteLine(0, auditionTarget: false).clearsAudition,
        isFalse,
      );
    });

    test('an out-of-range row is a no-op', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      expect(entry.controller.deleteLine(5).applied, isFalse);
      expect(entry.controller.document!.lines, hasLength(1));
    });
  });

  group('addLine and insertLineAt', () {
    test('an empty document gets a row at five seconds', () {
      final entry = build(loaded: document(const []));

      final result = entry.controller.addLine();

      final added = entry.controller.document!.lines.single;
      expect(added.text, isEmpty);
      expect(added.startTime, const Duration(seconds: 5));
      expect(added.endTime, const Duration(seconds: 10));
      expect(added.id, isNotNull);
      expect(entry.controller.selectedLineIndex, 0);
      expect(result.applied, isTrue);
      expect(entry.controller.hasChanges, isTrue);
    });

    test('a new row starts where the last one ended', () {
      final entry = build(
        loaded: document([line('a', startMs: 0, endMs: 2000, id: 'a')]),
      );

      entry.controller.addLine();

      expect(
        entry.controller.document!.lines.last.startTime,
        const Duration(seconds: 2),
      );
      expect(entry.controller.selectedLineIndex, 1);
    });

    test('inserting at a playback position keeps the rows sorted', () {
      final entry = build(
        loaded: document([
          line('a', startMs: 0, endMs: 2000, id: 'a'),
          line('c', startMs: 4000, endMs: 6000, id: 'c'),
        ]),
      );

      final result = entry.controller.insertLineAt(
        const Duration(milliseconds: 2500),
      );

      expect(result.insertedLineIndex, 1);
      expect(entry.controller.selectedLineIndex, 1);
      expect(entry.controller.document!.lines.map((row) => row.text), [
        'a',
        '',
        'c',
      ]);
      expect(entry.controller.document!.lines[1].id, isNotNull);
    });

    test('inserting drops row-indexed fallback metadata', () {
      final entry = build(
        loaded: document(
          [line('a', startMs: 0, endMs: 2000, id: 'a')],
          metadata: const {'fallbackCandidateCount': 2, 'untouched': 'kept'},
        ),
      );

      entry.controller.insertLineAt(const Duration(milliseconds: 500));

      expect(entry.controller.document!.metadata, {'untouched': 'kept'});
    });

    test('adding and inserting are undoable', () {
      final entry = build(loaded: document(const []));
      entry.controller.addLine();

      entry.controller.undo();

      expect(entry.controller.document!.lines, isEmpty);
      expect(entry.controller.undoLabel, isNull);
    });
  });

  group('updateGlobalOffset', () {
    test('stores the offset and leaves the selection alone', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.select(1);

      entry.controller.updateGlobalOffset(const Duration(milliseconds: 250));

      expect(
        entry.controller.document!.globalOffset,
        const Duration(milliseconds: 250),
      );
      expect(entry.controller.selectedLineIndex, 1);
      expect(entry.controller.hasChanges, isTrue);
    });

    test('nudging inside the merge window is one undo step', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      entry.controller.updateGlobalOffset(const Duration(milliseconds: 100));
      entry.controller.updateGlobalOffset(const Duration(milliseconds: 200));

      expect(entry.controller.history.undoDepth, 1);
      entry.controller.undo();
      expect(entry.controller.document!.globalOffset, isNull);
    });
  });

  group('setLineReviewed', () {
    test('marking a row reviewed is applied and undoable', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      final result = entry.controller.setLineReviewed(0, reviewed: true);

      expect(result.applied, isTrue);
      expect(
        const LyricReviewDecisionService().isReviewed(
          entry.controller.document!,
          0,
        ),
        isTrue,
      );
      expect(entry.controller.undoLabel, '标记第 1 行为已复核');
      entry.controller.undo();
      expect(
        const LyricReviewDecisionService().isReviewed(
          entry.controller.document!,
          0,
        ),
        isFalse,
      );
    });

    test('re-marking an already reviewed row is not a phantom undo step', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.setLineReviewed(0, reviewed: true);

      // The decision service would hand back a fresh document (new timestamp)
      // even when nothing changed, so the controller has to notice first.
      expect(
        entry.controller.setLineReviewed(0, reviewed: true).applied,
        isFalse,
      );
      expect(
        entry.controller.setLineReviewed(9, reviewed: false).applied,
        isFalse,
      );
      expect(entry.controller.history.undoDepth, 1);
    });

    test('un-reviewing an ordinary row is applied and undoable', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.setLineReviewed(0, reviewed: true);

      final result = entry.controller.setLineReviewed(0, reviewed: false);

      expect(result.applied, isTrue);
      expect(entry.controller.undoLabel, '取消第 1 行的复核标记');
      expect(
        const LyricReviewDecisionService().isReviewed(
          entry.controller.document!,
          0,
        ),
        isFalse,
      );
    });
  });

  group('batch changes', () {
    test('an ordinary edit drops the batch snapshot', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.replaceDocument(
        document([line('aligned', id: 'a')]),
        label: '应用参考歌词对齐',
        selectedLineIndex: 0,
        keepBatchSnapshot: true,
      );
      expect(entry.controller.alignmentSnapshot, isNotNull);

      entry.controller.updateLine(0, line('edited', id: 'a'));

      expect(entry.controller.alignmentSnapshot, isNull);
      expect(entry.controller.undoBatchChange().applied, isFalse);
    });

    test(
      'undoing the batch restores document, marks, selection and dirtiness',
      () {
        final original = document([line('a', id: 'a'), line('b', id: 'b')]);
        final entry = build(loaded: original);
        entry.controller.updateLine(
          1,
          line('b fixed', startMs: 1000, endMs: 2000, id: 'b'),
        );
        entry.controller.select(0);
        final dirtyBefore = entry.controller.hasChanges;

        entry.controller.replaceDocument(
          document([line('merged', id: 'm')]),
          label: '应用校对提案',
          selectedLineIndex: 0,
          keepBatchSnapshot: true,
          isReferenceProofread: true,
        );
        expect(
          entry.controller.alignmentSnapshot!.isReferenceProofread,
          isTrue,
        );
        expect(entry.controller.manuallyEditedLineIds, {'b'});

        final undone = entry.controller.undoBatchChange();

        expect(undone.applied, isTrue);
        expect(undone.clearsAudition, isTrue);
        expect(entry.controller.document!.lines.map((row) => row.text), [
          'a',
          'b fixed',
        ]);
        expect(entry.controller.manuallyEditedLineIds, {'b'});
        expect(entry.controller.selectedLineIndex, 0);
        expect(entry.controller.hasChanges, dirtyBefore);
        expect(entry.controller.alignmentSnapshot, isNull);
        // The reversal is itself an edit, so it appears in the history.
        expect(entry.controller.undoLabel, '撤销参考对齐');
      },
    );

    test('a selection can be cleared by the replacement', () {
      final entry = build(loaded: document([line('a', id: 'a')]));

      entry.controller.replaceDocument(
        document(const []),
        label: '应用校对提案',
        selectedLineIndex: null,
      );

      expect(entry.controller.selectedLineIndex, isNull);
      expect(entry.controller.document!.lines, isEmpty);
    });
  });

  group('restoreDocument', () {
    test('keeps only the manual marks that survived the restore', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(0, line('a fixed', id: 'a'));

      entry.controller.restoreDocument(
        document([line('a', id: 'a'), line('c', id: 'c')]),
        label: '恢复对齐前版本',
      );

      expect(entry.controller.manuallyEditedLineIds, {'a'});
      expect(entry.controller.protectedIndices, {0});
      expect(entry.controller.undoLabel, '恢复对齐前版本');
    });

    test('picks up marks persisted in the restored metadata', () {
      final restored = const LyricManualEditMarkerService().persist(
        document([line('a', id: 'a'), line('b', id: 'b')]),
        {'b'},
      );
      final entry = build(loaded: document([line('*', id: '*')]));

      entry.controller.restoreDocument(
        document([line('a', id: 'a'), line('b', id: 'b')], metadata: restored),
        label: '恢复对齐前版本',
      );

      expect(entry.controller.manuallyEditedLineIds, {'b'});
    });

    test('clamps a selection that no longer exists', () {
      final entry = build(
        loaded: document([
          line('a', id: 'a'),
          line('b', id: 'b'),
          line('c', id: 'c'),
        ]),
      );
      entry.controller.select(2);

      entry.controller.restoreDocument(
        document([line('a', id: 'a')]),
        label: '恢复对齐前版本',
      );

      expect(entry.controller.selectedLineIndex, 0);
    });
  });

  group('saving', () {
    test('documentForSave persists this session manual edit marks', () {
      final entry = build(loaded: document([line('a', id: 'a')]));
      entry.controller.updateLine(0, line('a fixed', id: 'a'));

      final saved = entry.controller.documentForSave();

      expect(
        saved.metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey],
        ['a'],
      );
    });

    test('documentForSave refuses to invent a document', () {
      final entry = build();

      expect(entry.controller.documentForSave, throwsStateError);
    });

    test(
      'markSaved clears dirtiness and the batch snapshot but keeps history',
      () {
        final entry = build(loaded: document([line('a', id: 'a')]));
        entry.controller.replaceDocument(
          document([line('a2', id: 'a')]),
          label: '应用校对提案',
          selectedLineIndex: 0,
          keepBatchSnapshot: true,
        );

        entry.controller.markSaved();

        expect(entry.controller.hasChanges, isFalse);
        expect(entry.controller.alignmentSnapshot, isNull);
        expect(entry.controller.canUndo, isTrue);
      },
    );
  });

  group('protectedIndices', () {
    test('follows a line id through a reorder', () {
      final entry = build(
        loaded: document([line('a', id: 'a'), line('b', id: 'b')]),
      );
      entry.controller.updateLine(
        1,
        line('b fixed', startMs: 1000, endMs: 2000, id: 'b'),
      );
      expect(entry.controller.protectedIndices, {1});

      entry.controller.replaceDocument(
        document([
          line('b fixed', startMs: 1000, endMs: 2000, id: 'b'),
          line('a', id: 'a'),
        ]),
        label: '应用参考歌词对齐',
        selectedLineIndex: 0,
      );

      expect(entry.controller.protectedIndices, {0});
    });
  });
}
