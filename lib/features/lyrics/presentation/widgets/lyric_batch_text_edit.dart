import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';

/// The document-wide text tools in the proofreading menu.
enum LyricBatchTextTool {
  findReplace,
  repetitionConsistency,
  textCleanup,

  /// Splits over-long rows and merges fragments (整理断行).
  lineStructure,

  /// Repairs overlaps, missing ends and out-of-order starts (检查时间轴).
  timelineRepair,

  /// Moves or stretches the timestamps of a range of rows (平移/伸缩时间轴).
  timingShift,

  /// Re-times rows by pressing a key as each one is sung (打轴).
  tapSync,

  /// Times every sung unit by pressing a key as it is sung (逐字打轴).
  wordTap,

  /// Finds rows sung implausibly fast or slow (语速异常检查).
  paceCheck,

  /// Cuts down phrases and rows the recogniser repeated (识别循环检查).
  asrLoopCheck,

  /// Lists invalid, drifted and suspicious word timing (逐字时间检查).
  wordTimingCheck,

  /// Fine-tunes the selected row's word timing (逐字微调).
  wordTimingEdit,

  /// Finds chants and backing vocals the recogniser shortened (漏唱和声检查).
  missedRepeatCheck,

  /// Re-recognises or re-aligns a stretch of rows (重新识别这一段).
  spanRecognition,

  /// Recognises singing the vocal check found without lyrics and inserts it
  /// (识别有人声没歌词的段落, D-045).
  vocalGapRecognition,

  /// Puts rows the vocal check removed back (恢复人声检查删除的行, D-045).
  restoreRemovedLines,
}

/// What a batch text tool (find-and-replace, repeated-line consistency, text
/// clean-up) hands back to the editor after the user confirmed its preview.
///
/// The tool works on a snapshot of the editing document; the editor applies
/// [document] as one undoable change only if that snapshot is still current.
class LyricBatchTextEdit {
  /// The edited document.
  final LyricDocument document;

  /// Undo-history label.
  final String label;

  /// Snack bar text; always says that nothing was written to disk.
  final String message;

  /// Row to select after applying.
  final int? selectedLineIndex;

  /// Ids of rows whose new text the user chose explicitly; the editor
  /// protects them like hand edits so later proofreading leaves them alone.
  final Set<String> manuallyEditedLineIds;

  const LyricBatchTextEdit({
    required this.document,
    required this.label,
    required this.message,
    required this.selectedLineIndex,
    this.manuallyEditedLineIds = const {},
  });
}

/// The shared frame of the batch text dialogs: responsive insets, a bounded
/// scrollable body and wrapping action buttons, so every tool stays usable at
/// small window sizes and large text scales.
class LyricBatchEditDialogFrame extends StatelessWidget {
  const LyricBatchEditDialogFrame({
    super.key,
    required this.title,
    required this.children,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.onConfirm,
    this.confirmKey,
  });

  final String title;
  final List<Widget> children;
  final String confirmLabel;
  final IconData confirmIcon;

  /// Null disables the confirm button.
  final VoidCallback? onConfirm;
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final maxWidth = spec.isCompact ? 520.0 : 640.0;
    final maxHeight =
        (media.size.height -
                media.viewInsets.bottom -
                spec.pageGutter * 2 -
                160)
            .clamp(240.0, 620.0)
            .toDouble();
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      titlePadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        spec.pageGutter,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        0,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        spec.pageGutter,
      ),
      title: Text(title),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: confirmKey,
          onPressed: onConfirm,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          icon: Icon(confirmIcon, size: 18),
          label: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// One row of a batch preview: row number, old text struck through, new text.
///
/// [highlights] marks UTF-16 ranges of [before] (for example the matches of a
/// search) in the accent colour. When [onSelectedChanged] is given the row
/// gets a checkbox so the user can leave it out.
class LyricBatchChangeRow extends StatelessWidget {
  const LyricBatchChangeRow({
    super.key,
    required this.index,
    required this.before,
    required this.after,
    this.note,
    this.highlights = const [],
    this.selected = true,
    this.onSelectedChanged,
    this.removal = false,
  });

  final int index;
  final String before;

  /// Null for a row that is deleted.
  final String? after;
  final String? note;
  final List<(int, int)> highlights;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  /// The row is deleted rather than rewritten.
  final bool removal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      decoration: TextDecoration.lineThrough,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            '第 ${index + 1} 行',
            if (removal) '将删除',
            if (note != null && note!.isNotEmpty) note!,
          ].join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
            color: removal ? AppColors.warning : AppColors.textTertiary,
          ),
        ),
        Text.rich(
          _highlighted(
            before.isEmpty ? '（空行）' : before,
            before.isEmpty ? const [] : highlights,
            muted,
            muted?.copyWith(color: AppColors.warning),
          ),
        ),
        if (after != null) Text(after!, style: theme.textTheme.bodyMedium),
      ],
    );
    final callback = onSelectedChanged;
    if (callback == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: body,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: selected,
        onChanged: (value) => callback(value ?? false),
        title: body,
      ),
    );
  }

  static TextSpan _highlighted(
    String text,
    List<(int, int)> ranges,
    TextStyle? base,
    TextStyle? accent,
  ) {
    if (ranges.isEmpty) return TextSpan(text: text, style: base);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final (start, end) in ranges) {
      if (start < cursor || end > text.length || start >= end) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: accent));
      cursor = end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: base, children: spans);
  }
}

/// A short muted paragraph used for explanations inside the dialogs.
class LyricBatchNote extends StatelessWidget {
  const LyricBatchNote(this.text, {super.key, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: warning ? AppColors.warning : AppColors.textSecondary,
      ),
    );
  }
}
