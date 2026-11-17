import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_asr_loop_detector.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the recognition loop check.
class LyricAsrLoopStrings {
  const LyricAsrLoopStrings._();

  static const String actionTitle = '识别循环检查';
  static const String actionDetail =
      '找出识别器卡住时反复输出的句子：一行里重复十几遍，连续多行完全相同，或两三句来回循环';
  static const String intro =
      '语音识别在长音、间奏或伴奏很响时容易“卡住”，把同一句反复输出。'
      '一行里同一个词句连续重复很多次时，建议只保留前几遍；'
      '连续多行文字完全相同时，建议保留前两行、删除其余；'
      '两到四句一组来回循环（甲乙甲乙甲乙……）时，建议保留前两遍。'
      '歌曲本身也会重复，所以只有远超常见重复次数的才默认勾选，其余请试听后决定。'
      '手动编辑过的行只提示不修改。结果可撤销，保存后才写盘。';

  static String applied(int rewritten, int removed) {
    final parts = [
      if (rewritten > 0) '已删减 $rewritten 行内的重复',
      if (removed > 0) '已删除 $removed 行重复行',
    ];
    return '${parts.join('，')}（未写入磁盘）';
  }

  static String runNote(LyricAsrLoopRun run) =>
      '「${run.unit}」连续 ${run.repeats} 遍，保留 ${run.kept} 遍';

  static String note(LyricAsrLoopIssue issue) {
    final strength = issue.strong ? '' : '（可能是歌词本身的重复，请试听）';
    final protected = issue.protected ? '（手动编辑过，不修改）' : '';
    return switch (issue.kind) {
      LyricAsrLoopKind.inRowRepeat =>
        '行内循环：${issue.runs.map(runNote).join('；')}$strength$protected',
      LyricAsrLoopKind.repeatedRows =>
        '连续 ${issue.runIndices.length} 行相同，'
            '删除 ${issue.removedIndices.length} 行$strength$protected',
      LyricAsrLoopKind.repeatedBlock =>
        '${issue.blockRows} 行一组连续循环 ${issue.repeats} 遍，'
            '删除 ${issue.removedIndices.length} 行$strength$protected',
    };
  }
}

/// Shows the recognition loop check. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricAsrLoopDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  ValueChanged<int>? onPreviewLine,
  LyricAsrLoopDetector detector = const LyricAsrLoopDetector(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricAsrLoopDialog(
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: onPreviewLine,
      detector: detector,
    ),
  );
}

/// Lists recognition loops with a proposed fix each; the selected fixes are
/// applied as one undoable change.
class LyricAsrLoopDialog extends StatefulWidget {
  const LyricAsrLoopDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.onPreviewLine,
    this.detector = const LyricAsrLoopDetector(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final ValueChanged<int>? onPreviewLine;
  final LyricAsrLoopDetector detector;

  /// How many findings the preview lists.
  static const int previewLimit = 60;

  /// How many deleted rows a repeated-rows finding shows.
  static const int removedPreviewLimit = 3;

  @override
  State<LyricAsrLoopDialog> createState() => _LyricAsrLoopDialogState();
}

class _LyricAsrLoopDialogState extends State<LyricAsrLoopDialog> {
  late final LyricAsrLoopPlan _plan = widget.detector.plan(
    widget.document,
    protectedIndices: widget.protectedIndices,
  );
  late final Set<int> _selected = _plan.defaultPositions.toSet();

  void _confirm() {
    if (_selected.isEmpty) return;
    final counts = _plan.countFor(_selected);
    final first = _selected
        .map((position) => _plan.issues[position].index)
        .reduce((a, b) => a < b ? a : b);
    final document = _plan.applyTo(widget.document, _selected);
    final last = document.lines.length - 1;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: document,
        label: LyricAsrLoopStrings.actionTitle,
        message: LyricAsrLoopStrings.applied(counts.rewritten, counts.removed),
        selectedLineIndex: last < 0 ? null : (first > last ? last : first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final fixable = plan.fixablePositions;
    final counts = plan.countFor(_selected);
    final inRow = plan.issues
        .where((issue) => issue.kind == LyricAsrLoopKind.inRowRepeat)
        .length;
    final rowRuns = plan.issues.length - inRow;
    final shown = plan.issues.length < LyricAsrLoopDialog.previewLimit
        ? plan.issues.length
        : LyricAsrLoopDialog.previewLimit;

    return LyricBatchEditDialogFrame(
      title: LyricAsrLoopStrings.actionTitle,
      confirmKey: const ValueKey('asr_loop_confirm'),
      confirmIcon: Icons.repeat_one_rounded,
      confirmLabel: _selected.isEmpty
          ? (fixable.isEmpty ? '没有可自动处理的循环' : '请选择要处理的项')
          : [
              if (counts.rewritten > 0) '删减 ${counts.rewritten} 行',
              if (counts.removed > 0) '删除 ${counts.removed} 行',
            ].join('，'),
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricAsrLoopStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        Text(
          plan.issues.isEmpty
              ? '没有发现识别循环。'
              : '行内循环 $inRow 处，连续重复行 $rowRuns 组；'
                    '默认勾选 ${plan.defaultPositions.length} 项明显的循环。',
          key: const ValueKey('asr_loop_summary'),
          style: theme.textTheme.titleSmall,
        ),
        if (fixable.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('asr_loop_toggle_all'),
              onPressed: () => setState(() {
                final selectAll = _selected.length != fixable.length;
                _selected.clear();
                if (selectAll) _selected.addAll(fixable);
              }),
              child: Text(_selected.length == fixable.length ? '全不选' : '全选'),
            ),
          ),
        ],
        for (var position = 0; position < shown; position++)
          _LoopRow(
            key: ValueKey('asr_loop_issue_$position'),
            issue: plan.issues[position],
            document: widget.document,
            selected: _selected.contains(position),
            onSelectedChanged: plan.issues[position].fixable
                ? (value) => setState(
                    () => value
                        ? _selected.add(position)
                        : _selected.remove(position),
                  )
                : null,
            onPreview: widget.onPreviewLine == null
                ? null
                : () => widget.onPreviewLine!(plan.issues[position].index),
          ),
        if (plan.issues.length > shown)
          LyricBatchNote('另有 ${plan.issues.length - shown} 项未列出，它们保持当前勾选状态。'),
      ],
    );
  }
}

class _LoopRow extends StatelessWidget {
  const _LoopRow({
    super.key,
    required this.issue,
    required this.document,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPreview,
  });

  final LyricAsrLoopIssue issue;
  final LyricDocument document;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final line = document.lines[issue.index];
    final note = LyricAsrLoopStrings.note(issue);
    final Widget body;
    if (issue.kind == LyricAsrLoopKind.inRowRepeat) {
      body = LyricBatchChangeRow(
        index: issue.index,
        before: line.text,
        after: issue.fixable ? issue.proposedText : null,
        note: note,
        highlights: [for (final run in issue.runs) (run.keptEnd, run.end)],
        selected: selected,
        onSelectedChanged: onSelectedChanged,
      );
    } else {
      final removed = issue.removedIndices;
      final shown = removed.take(LyricAsrLoopDialog.removedPreviewLimit);
      final rest = removed.length - shown.length;
      body = LyricBatchChangeRow(
        index: issue.index,
        before: [
          '第 ${issue.runIndices.first + 1}–${issue.runIndices.last + 1} 行：'
              '${line.text.trim()}',
          for (final row in shown)
            '删除第 ${row + 1} 行 ${_span(document.lines[row])}',
          if (rest > 0) '……另有 $rest 行',
        ].join('\n'),
        after: null,
        note: note,
        removal: issue.fixable,
        selected: selected,
        onSelectedChanged: onSelectedChanged,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: onSelectedChanged == null
              ? DefaultTextStyle.merge(
                  style: const TextStyle(color: AppColors.textSecondary),
                  child: body,
                )
              : body,
        ),
        if (onPreview != null)
          IconButton(
            tooltip: '试听第 ${issue.index + 1} 行',
            onPressed: onPreview,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
      ],
    );
  }

  static String _span(LyricLine line) =>
      '${_clock(line.startTime)}–${_clock(line.endTime)}';

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inMilliseconds % 60000) / 1000;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
