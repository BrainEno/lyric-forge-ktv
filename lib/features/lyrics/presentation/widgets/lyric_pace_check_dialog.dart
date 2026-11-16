import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_pace_analyzer.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the pace check.
class LyricPaceCheckStrings {
  const LyricPaceCheckStrings._();

  static const String actionTitle = '语速异常检查';
  static const String actionDetail = '找出唱得过快或过慢的行：常见于结束被截断、跨过间奏或漏字多字';
  static const String intro =
      '按全曲自己的语速（每秒唱几个字的中位数）逐行比较。'
      '过快的行多半是结束时间被截在换气处、开始偏晚，或识别多出了字；'
      '过慢的行多半是把间奏算进了这一行、开始过早，或漏识别了一句。'
      '能从时间上修正的给出建议结束时间，默认勾选；文字问题请试听后在列表里改。'
      '歌词文字不会改变；手动打轴过的行只提示不修改。结果可撤销，保存后才写盘。';

  static String applied(int rows) => '已调整 $rows 行的结束时间（未写入磁盘）';

  static String rate(double value) => '每秒 ${value.toStringAsFixed(1)} 字';

  static String note(LyricPaceIssue issue, double median) {
    final factor = issue.factor(median).toStringAsFixed(1);
    return switch (issue.kind) {
      LyricPaceIssueKind.crowded =>
        '过快：${rate(issue.rate)}，约为全曲的 $factor 倍'
            '${issue.fixable ? '，建议延后结束' : '，后面没有空隙，请试听核对文字或开始时间'}',
      LyricPaceIssueKind.sparse =>
        '过慢：${rate(issue.rate)}，只有全曲的 1/$factor'
            '${issue.fixable ? '，建议提前结束' : '，请试听是否漏字或开始过早'}',
    };
  }

  static String span(Duration start, Duration end) =>
      '${formatLyricTimeInput(start)} → ${formatLyricTimeInput(end)}';
}

/// Shows the pace check. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricPaceCheckDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  ValueChanged<int>? onPreviewLine,
  LyricPaceAnalyzer analyzer = const LyricPaceAnalyzer(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricPaceCheckDialog(
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: onPreviewLine,
      analyzer: analyzer,
    ),
  );
}

class LyricPaceCheckDialog extends StatefulWidget {
  const LyricPaceCheckDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.onPreviewLine,
    this.analyzer = const LyricPaceAnalyzer(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final ValueChanged<int>? onPreviewLine;
  final LyricPaceAnalyzer analyzer;

  /// How many rows the preview lists.
  static const int previewLimit = 60;

  @override
  State<LyricPaceCheckDialog> createState() => _LyricPaceCheckDialogState();
}

class _LyricPaceCheckDialogState extends State<LyricPaceCheckDialog> {
  late final LyricPacePlan _plan = widget.analyzer.plan(
    widget.document,
    protectedIndices: widget.protectedIndices,
  );
  late final Set<int> _selected = _plan.fixablePositions.toSet();

  void _confirm() {
    if (_selected.isEmpty) return;
    final first = _selected
        .map((position) => _plan.issues[position].index)
        .reduce((a, b) => a < b ? a : b);
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: _plan.applyTo(widget.document, _selected),
        label: LyricPaceCheckStrings.actionTitle,
        message: LyricPaceCheckStrings.applied(_selected.length),
        selectedLineIndex: first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final crowded = plan.issues
        .where((issue) => issue.kind == LyricPaceIssueKind.crowded)
        .length;
    final sparse = plan.issues.length - crowded;
    final fixable = plan.fixablePositions;
    final shown = plan.issues.length.clamp(
      0,
      LyricPaceCheckDialog.previewLimit,
    );

    return LyricBatchEditDialogFrame(
      title: LyricPaceCheckStrings.actionTitle,
      confirmKey: const ValueKey('pace_check_confirm'),
      confirmIcon: Icons.speed_rounded,
      confirmLabel: _selected.isEmpty
          ? (fixable.isEmpty ? '没有可自动调整的行' : '请选择要调整的行')
          : '调整 ${_selected.length} 行',
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricPaceCheckStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        Text(
          plan.issues.isEmpty
              ? '没有发现语速异常的行。'
              : '过快 $crowded 行，过慢 $sparse 行；其中 ${fixable.length} 行可按时间调整。',
          key: const ValueKey('pace_check_summary'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        LyricBatchNote(
          plan.measured
              ? '全曲语速中位数：${LyricPaceCheckStrings.rate(plan.medianRate)}。'
              : '可比较的行太少，按默认语速'
                    '（${LyricPaceCheckStrings.rate(plan.medianRate)}）判断，仅供参考。',
          warning: !plan.measured,
        ),
        if (fixable.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('pace_check_toggle_all'),
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
          _PaceRow(
            key: ValueKey('pace_issue_$position'),
            issue: plan.issues[position],
            medianRate: plan.medianRate,
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
          LyricBatchNote('另有 ${plan.issues.length - shown} 行未列出，它们保持当前勾选状态。'),
      ],
    );
  }
}

class _PaceRow extends StatelessWidget {
  const _PaceRow({
    super.key,
    required this.issue,
    required this.medianRate,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPreview,
  });

  final LyricPaceIssue issue;
  final double medianRate;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final line = issue.before;
    final text = line.text.trim();
    final end = issue.proposedEnd;
    final before =
        '${LyricPaceCheckStrings.span(line.startTime, line.endTime)}'
        '${text.isEmpty ? '' : '  $text'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: end == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第 ${issue.index + 1} 行 · '
                        '${LyricPaceCheckStrings.note(issue, medianRate)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                      Text(before),
                    ],
                  ),
                )
              : LyricBatchChangeRow(
                  index: issue.index,
                  before: before,
                  after: LyricPaceCheckStrings.span(line.startTime, end),
                  note: LyricPaceCheckStrings.note(issue, medianRate),
                  selected: selected,
                  onSelectedChanged: onSelectedChanged,
                ),
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
}
