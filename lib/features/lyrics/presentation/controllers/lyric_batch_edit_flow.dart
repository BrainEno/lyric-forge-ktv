import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/lyric_batch_shift_dialog.dart';
import '../widgets/lyric_line_delete_undo.dart';
import 'lyric_editor_document_controller.dart';

/// Runs the batch edits of the lyric list on the chosen rows (D-066): the
/// dialogs, the editor call and the 撤销 offer that follows.
///
/// The editor does the edit; this decides what the user sees around it. An
/// applied edit is reported to [onEdit] without its message (the screen would
/// show it as a plain notice), and the message comes back here with 撤销.
class LyricBatchEditFlow {
  const LyricBatchEditFlow({
    required this.editor,
    required this.onUndo,
    this.onEdit,
    this.audioDuration,
    this.auditionLineIndex,
  });

  final LyricEditorDocumentController editor;
  final VoidCallback onUndo;
  final ValueChanged<LyricEditResult>? onEdit;
  final Duration? audioDuration;

  /// The row being auditioned, if any: an edit that moves or removes it
  /// makes the audition stale.
  final int? auditionLineIndex;

  List<int> get _rows => editor.batchSelection;

  bool _touchesAudition(List<int> rows) {
    final audition = auditionLineIndex;
    return audition != null && rows.contains(audition);
  }

  void markReviewed(BuildContext context, {required bool reviewed}) =>
      _finish(context, editor.setLinesReviewed(_rows, reviewed: reviewed));

  void delete(BuildContext context) {
    final rows = _rows;
    _finish(
      context,
      editor.deleteLines(rows, auditionTarget: _touchesAudition(rows)),
    );
  }

  void merge(BuildContext context) {
    final rows = _rows;
    _finish(
      context,
      editor.mergeLines(rows, auditionTarget: _touchesAudition(rows)),
    );
  }

  Future<void> shift(BuildContext context) async {
    final document = editor.document;
    final rows = _rows;
    if (document == null || rows.isEmpty) return;
    final delta = await showLyricBatchShiftDialog(
      context,
      document: document,
      rows: rows,
      audioDuration: audioDuration,
    );
    if (delta == null || !context.mounted) return;
    final current = _rows;
    _finish(
      context,
      editor.shiftLines(
        current,
        delta,
        audioDuration: audioDuration,
        auditionTarget: _touchesAudition(current),
      ),
    );
  }

  /// Copies the chosen rows' text, one row per line.
  void copy(BuildContext context) {
    final document = editor.document;
    final rows = _rows;
    if (document == null || rows.isEmpty) return;
    final text = [for (final row in rows) document.lines[row].text].join('\n');
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已复制 ${rows.length} 行歌词')));
  }

  void _finish(BuildContext context, LyricEditResult result) {
    final message = result.hint;
    if (!result.applied) {
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    onEdit?.call(LyricEditResult(clearsAudition: result.clearsAudition));
    if (!context.mounted) return;
    offerLyricEditUndo(
      context,
      message: message ?? '已完成批量修改',
      revision: () => editor.documentRevision,
      undo: onUndo,
    );
  }
}
