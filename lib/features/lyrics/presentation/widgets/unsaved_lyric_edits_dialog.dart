import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';

/// What the user chose when leaving the editor with unsaved changes.
enum UnsavedLyricEditsDecision {
  /// Keep editing; nothing is saved and the editor stays open.
  stay,

  /// Leave without saving.
  discard,

  /// Save first, then leave.
  save,
}

/// Asks whether to save before leaving the lyric editor.
///
/// Dismissing the dialog counts as [UnsavedLyricEditsDecision.stay]: the safe
/// default for a barrier tap is "do nothing", never "throw the edits away".
Future<UnsavedLyricEditsDecision> confirmUnsavedLyricEdits(
  BuildContext context,
) async {
  final decision = await showDialog<UnsavedLyricEditsDecision>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('有未保存的修改'),
      content: const Text('返回前是否保存当前歌词修改？未保存的更改将会丢失。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(UnsavedLyricEditsDecision.stay),
          child: const Text('继续编辑'),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(UnsavedLyricEditsDecision.discard),
          child: const Text('放弃修改'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(UnsavedLyricEditsDecision.save),
          child: const Text('保存并返回'),
        ),
      ],
    ),
  );
  return decision ?? UnsavedLyricEditsDecision.stay;
}
