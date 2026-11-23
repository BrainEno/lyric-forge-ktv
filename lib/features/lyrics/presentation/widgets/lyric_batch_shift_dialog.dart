import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_line_batch_service.dart';
import '../../domain/services/lyric_timing_shift_service.dart';

/// Asks how far to move the chosen rows (D-066). Returns the offset, or
/// null when cancelled.
Future<Duration?> showLyricBatchShiftDialog(
  BuildContext context, {
  required LyricDocument document,
  required List<int> rows,
  Duration? audioDuration,
}) {
  return showDialog<Duration>(
    context: context,
    builder: (_) => LyricBatchShiftDialog(
      document: document,
      rows: rows,
      audioDuration: audioDuration,
    ),
  );
}

/// Moves only the chosen rows, which need not be next to each other; the
/// range tool (平移 / 伸缩时间轴) still handles a whole stretch of a song.
class LyricBatchShiftDialog extends StatefulWidget {
  const LyricBatchShiftDialog({
    super.key,
    required this.document,
    required this.rows,
    this.audioDuration,
    this.service = const LyricLineBatchService(),
  });

  final LyricDocument document;
  final List<int> rows;
  final Duration? audioDuration;
  final LyricLineBatchService service;

  static const offsetKey = ValueKey('batch_shift_offset');
  static const confirmKey = ValueKey('batch_shift_confirm');
  static ValueKey<String> nudgeKey(int milliseconds) =>
      ValueKey('batch_shift_nudge_$milliseconds');

  /// The quick steps, in milliseconds.
  static const steps = [-1000, -100, 100, 1000];

  /// How many moved rows the preview lists.
  static const previewLimit = 3;

  @override
  State<LyricBatchShiftDialog> createState() => _LyricBatchShiftDialogState();
}

class _LyricBatchShiftDialogState extends State<LyricBatchShiftDialog> {
  final _offset = TextEditingController(text: '0.00');
  Duration? _delta = Duration.zero;
  LyricBatchShiftResult? _result;

  @override
  void initState() {
    super.initState();
    _offset.addListener(_recompute);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _recompute() {
    final delta = parseLyricTimeInput(_offset.text);
    setState(() {
      _delta = delta;
      _result = delta == null || delta == Duration.zero
          ? null
          : widget.service.shift(
              widget.document,
              widget.rows,
              delta,
              audioDuration: widget.audioDuration,
            );
    });
  }

  void _nudge(int milliseconds) {
    final current = parseLyricTimeInput(_offset.text) ?? Duration.zero;
    final next = current + Duration(milliseconds: milliseconds);
    _offset.text = (next.inMilliseconds / 1000).toStringAsFixed(2);
  }

  static String _step(int milliseconds) {
    final sign = milliseconds > 0 ? '+' : '-';
    return '$sign${(milliseconds.abs() / 1000).toStringAsFixed(1)} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final delta = _delta;
    return AlertDialog(
      title: Text('平移 ${widget.rows.length} 行的时间'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选中各行的开始和结束时间一起提前或推后，文字和其他行不变。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: LyricBatchShiftDialog.offsetKey,
              controller: _offset,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '移动多少秒',
                helperText: '正数推后，负数提前',
                errorText: delta == null ? '请输入秒数，例如 0.5 或 -1.2' : null,
                isDense: true,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final step in LyricBatchShiftDialog.steps)
                  ActionChip(
                    key: LyricBatchShiftDialog.nudgeKey(step),
                    label: Text(_step(step)),
                    onPressed: () => _nudge(step),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ..._preview(theme, result),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: LyricBatchShiftDialog.confirmKey,
          onPressed: result?.isSuccess == true ? _confirm : null,
          child: const Text('平移'),
        ),
      ],
    );
  }

  void _confirm() {
    final delta = _delta;
    if (delta == null || _result?.isSuccess != true) return;
    Navigator.of(context).pop(delta);
  }

  List<Widget> _preview(ThemeData theme, LyricBatchShiftResult? result) {
    final style = theme.textTheme.bodySmall;
    if (result == null) {
      return [
        Text(
          '输入要移动的秒数后，这里会显示调整后的时间。',
          style: style?.copyWith(color: AppColors.textTertiary),
        ),
      ];
    }
    final after = result.document;
    if (after == null) {
      return [
        Text(
          '这样不会改变任何时间。',
          style: style?.copyWith(color: AppColors.textTertiary),
        ),
      ];
    }
    final moved = [
      for (final row in widget.rows)
        if (row < after.lines.length &&
            (after.lines[row].startTime !=
                    widget.document.lines[row].startTime ||
                after.lines[row].endTime != widget.document.lines[row].endTime))
          row,
    ];
    final issues = result.introducedIssues.length;
    return [
      for (final row in moved.take(LyricBatchShiftDialog.previewLimit))
        Text(
          '第 ${row + 1} 行  '
          '${formatLyricTimeInput(widget.document.lines[row].startTime)}'
          ' → ${formatLyricTimeInput(after.lines[row].startTime)}',
          style: style?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      if (moved.length > LyricBatchShiftDialog.previewLimit)
        Text(
          '…共 ${result.changedCount} 行',
          style: style?.copyWith(color: AppColors.textTertiary),
        ),
      if (result.clampedCount > 0)
        Text(
          '${result.clampedCount} 行已到歌曲开头或结尾，会停在边界。',
          style: style?.copyWith(color: AppColors.textSecondary),
        ),
      if (issues > 0) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          '会新增 $issues 处时间轴问题（例如和相邻的行重叠），'
          '确定后仍可以撤销。',
          style: style?.copyWith(color: AppColors.warning),
        ),
      ],
    ];
  }
}
