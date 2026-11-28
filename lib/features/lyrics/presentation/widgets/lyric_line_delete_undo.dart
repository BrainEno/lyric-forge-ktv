import 'package:flutter/material.dart';

import '../../../../core/widgets/undo_snack_bar.dart';

/// Offers 撤销 right after a lyric row is deleted (D-064).
///
/// The offer only takes the deletion back while nothing else has changed;
/// after a later edit, the toolbar undo (or Ctrl/Cmd+Z) walks the history
/// in order instead of skipping past newer edits.
void offerLyricLineDeleteUndo(
  BuildContext context, {
  required int lineNumber,
  required int Function() revision,
  required VoidCallback undo,
}) => offerLyricEditUndo(
  context,
  message: '已删除第 $lineNumber 行',
  revision: revision,
  undo: undo,
);

/// Shows [message] with 撤销 for the edit just made, such as a batch edit
/// (D-066), under the same rule as [offerLyricLineDeleteUndo].
void offerLyricEditUndo(
  BuildContext context, {
  required String message,
  required int Function() revision,
  required VoidCallback undo,
}) {
  final editedAt = revision();
  showUndoSnackBar(
    ScaffoldMessenger.of(context),
    message: message,
    onUndo: () async {
      if (!context.mounted) return null;
      if (revision() != editedAt) {
        return '之后又有修改，请用工具栏的撤销或 Ctrl/Cmd+Z';
      }
      undo();
      return null;
    },
  );
}
