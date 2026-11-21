import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/vocal_check_record.dart';
import '../../domain/services/lyric_vocal_check_actions.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_missed_repeat_dialog.dart' show LyricSpanPreview;
import 'lyric_span_recognition_dialog.dart' show LyricSpanRecognitionStrings;
import 'lyric_vocal_gap_dialog.dart' show LyricVocalCheckStrings;

/// The edit that puts every row the vocal check removed back, or null when
/// it removed none. The one-click "全部恢复" uses it without a dialog.
LyricBatchTextEdit? lyricRestoreAllRemovedLinesEdit(
  LyricDocument document, {
  LyricVocalCheckActions actions = const LyricVocalCheckActions(),
}) {
  final restore = actions.restoreAll(document);
  return restore == null ? null : _editFor(restore);
}

LyricBatchTextEdit _editFor(LyricVocalRestore restore) => LyricBatchTextEdit(
  document: restore.document,
  label: LyricVocalCheckStrings.restoreTitle,
  message: LyricVocalCheckStrings.restoredMessage(
    restore.count,
    overlapping: restore.overlapping,
  ),
  selectedLineIndex: restore.restoredIndices.first,
  manuallyEditedLineIds: restore.restoredIds,
);

/// Shows the removed rows with a checkbox each. Returns the confirmed edit,
/// or null.
Future<LyricBatchTextEdit?> showLyricVocalRestoreDialog(
  BuildContext context, {
  required LyricDocument document,
  LyricSpanPreview? onPreviewSpan,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricVocalRestoreDialog(
      document: document,
      onPreviewSpan: onPreviewSpan,
    ),
  );
}

/// Puts rows the vocal check removed back at their recognised times
/// (D-045). Every row starts checked: opening the dialog is already the
/// decision to look at them.
class LyricVocalRestoreDialog extends StatefulWidget {
  const LyricVocalRestoreDialog({
    super.key,
    required this.document,
    this.onPreviewSpan,
    this.actions = const LyricVocalCheckActions(),
  });

  final LyricDocument document;
  final LyricSpanPreview? onPreviewSpan;
  final LyricVocalCheckActions actions;

  @override
  State<LyricVocalRestoreDialog> createState() =>
      _LyricVocalRestoreDialogState();
}

class _LyricVocalRestoreDialogState extends State<LyricVocalRestoreDialog> {
  late final List<LyricVocalCheckRemovedLine> _removed;
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _removed =
        LyricVocalCheckRecord.fromMetadata(
          widget.document.metadata,
        )?.removedLines ??
        const [];
    _selected = {for (var index = 0; index < _removed.length; index++) index};
  }

  void _confirm() {
    final restore = widget.actions.restore(widget.document, _selected);
    if (restore == null) return;
    Navigator.of(context).pop(_editFor(restore));
  }

  int _anchorFor(LyricVocalCheckRemovedLine line) {
    final lines = widget.document.lines;
    if (lines.isEmpty) return 0;
    final at = widget.actions.insertionIndex(widget.document, line.start);
    return at >= lines.length ? lines.length - 1 : at;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _selected.length == _removed.length;
    final preview = widget.onPreviewSpan;
    return LyricBatchEditDialogFrame(
      title: LyricVocalCheckStrings.restoreTitle,
      confirmKey: const ValueKey('vocal_restore_confirm'),
      confirmIcon: Icons.settings_backup_restore_rounded,
      confirmLabel: _selected.isEmpty ? '请勾选要恢复的行' : '恢复 ${_selected.length} 行',
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricVocalCheckStrings.restoreIntro),
        const SizedBox(height: AppSpacing.sm),
        if (_removed.isEmpty)
          const LyricBatchNote(LyricVocalCheckStrings.noRemoved)
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '人声检查删除了 ${_removed.length} 行',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: const ValueKey('vocal_restore_toggle_all'),
                onPressed: () => setState(() {
                  if (all) {
                    _selected.clear();
                  } else {
                    _selected.addAll([
                      for (var index = 0; index < _removed.length; index++)
                        index,
                    ]);
                  }
                }),
                child: Text(all ? '全不选' : '全选'),
              ),
            ],
          ),
          for (final (index, line) in _removed.indexed)
            Row(
              key: ValueKey('vocal_restore_row_$index'),
              children: [
                Checkbox(
                  key: ValueKey('vocal_restore_check_$index'),
                  value: _selected.contains(index),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  }),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    '${LyricSpanRecognitionStrings.clock(line.start)}–'
                    '${LyricSpanRecognitionStrings.clock(line.end)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.text.trim().isEmpty ? '（空行）' : line.text.trim(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (preview != null &&
                    widget.document.lines.isNotEmpty &&
                    line.end > line.start)
                  IconButton(
                    key: ValueKey('vocal_restore_preview_$index'),
                    tooltip: '试听这一行原来的时间',
                    onPressed: () =>
                        preview(_anchorFor(line), line.start, line.end),
                    icon: const Icon(Icons.hearing_rounded, size: 18),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}
