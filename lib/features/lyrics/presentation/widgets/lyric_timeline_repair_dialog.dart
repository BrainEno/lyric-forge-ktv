import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_timeline_repair_planner.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the timeline check.
class LyricTimelineRepairStrings {
  const LyricTimelineRepairStrings._();

  static const String actionTitle = '检查时间轴';
  static const String actionDetail = '不需要参考歌词；修复重叠、缺失结束时间和顺序颠倒的行';
  static const String intro =
      '逐行检查开始和结束时间。能按相邻行推断的问题列在下面：'
      '与下一行重叠的收尾到下一行开始，结束不晚于开始的按字数估算结束时间，'
      '负数开始时间移到 0:00，超出音频的收尾到音频末尾。'
      '时间顺序颠倒的行会挪到上一行之后——这是推测，默认不勾选，请先试听。'
      '歌词文字和行的顺序不会改变；手动编辑过的行不会改动。结果可撤销，保存后才写盘。';

  static String applied(int rows) => '已修复 $rows 行的时间（未写入磁盘）';

  static String reason(LyricTimelineFixReason reason) => switch (reason) {
    LyricTimelineFixReason.negativeStart => '开始时间为负',
    LyricTimelineFixReason.outOfOrder => '时间顺序颠倒，挪到上一行之后',
    LyricTimelineFixReason.zeroDuration => '没有有效结束时间，按字数估算',
    LyricTimelineFixReason.overlapsNext => '与下一行重叠',
    LyricTimelineFixReason.shortGap => '与下一行空隙过短',
    LyricTimelineFixReason.pastAudioEnd => '超出音频末尾',
  };

  static String note(LyricTimelineFix fix) {
    final reasons = fix.reasons.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final text = reasons.map(reason).join('、');
    return fix.confident ? text : '$text，请先试听确认';
  }

  static String span(LyricLine line) =>
      '${formatLyricTimeInput(line.startTime)} → '
      '${formatLyricTimeInput(line.endTime)}';
}

/// Shows the timeline check. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricTimelineRepairDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  Duration? audioDuration,
  ValueChanged<int>? onPreviewLine,
  LyricTimelineRepairPlanner planner = const LyricTimelineRepairPlanner(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricTimelineRepairDialog(
      document: document,
      protectedIndices: protectedIndices,
      audioDuration: audioDuration,
      onPreviewLine: onPreviewLine,
      planner: planner,
    ),
  );
}

class LyricTimelineRepairDialog extends StatefulWidget {
  const LyricTimelineRepairDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.audioDuration,
    this.onPreviewLine,
    this.planner = const LyricTimelineRepairPlanner(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final Duration? audioDuration;

  /// Plays a row so a guessed slot can be checked by ear.
  final ValueChanged<int>? onPreviewLine;
  final LyricTimelineRepairPlanner planner;

  /// How many repairs and manual issues the preview lists.
  static const int previewLimit = 60;

  @override
  State<LyricTimelineRepairDialog> createState() =>
      _LyricTimelineRepairDialogState();
}

class _LyricTimelineRepairDialogState extends State<LyricTimelineRepairDialog> {
  late final LyricTimelineRepairPlan _plan;
  final Set<int> _selected = {};
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _plan = widget.planner.plan(
      widget.document,
      protectedIndices: widget.protectedIndices,
      audioDuration: widget.audioDuration,
    );
    for (var position = 0; position < _plan.fixes.length; position++) {
      if (_plan.fixes[position].confident) _selected.add(position);
    }
    _remaining = _countRemaining();
  }

  int _countRemaining() => widget.planner
      .remainingIssues(
        widget.document,
        _plan,
        _selected,
        audioDuration: widget.audioDuration,
      )
      .map((issue) => issue.lineIndex)
      .toSet()
      .length;

  void _update(VoidCallback change) => setState(() {
    change();
    _remaining = _countRemaining();
  });

  void _confirm() {
    if (_selected.isEmpty) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: _plan.applyTo(widget.document, _selected),
        label: LyricTimelineRepairStrings.actionTitle,
        message: LyricTimelineRepairStrings.applied(_selected.length),
        selectedLineIndex: _plan.selectionAfterApply(_selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final fixesShown = plan.fixes.length.clamp(
      0,
      LyricTimelineRepairDialog.previewLimit,
    );
    final manualShown = plan.manualIssues.length.clamp(
      0,
      LyricTimelineRepairDialog.previewLimit,
    );
    final skipped = plan.skippedProtectedIndices.length;
    final nothingFound = plan.isEmpty && plan.manualIssues.isEmpty;

    return LyricBatchEditDialogFrame(
      title: LyricTimelineRepairStrings.actionTitle,
      confirmKey: const ValueKey('timeline_repair_confirm'),
      confirmIcon: Icons.healing_rounded,
      confirmLabel: _selected.isEmpty
          ? (plan.isEmpty ? '没有可自动修复的行' : '请选择要修复的行')
          : '修复 ${_selected.length} 行',
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricTimelineRepairStrings.intro),
        if (widget.audioDuration == null) ...[
          const SizedBox(height: AppSpacing.xs),
          const LyricBatchNote('没有关联音频时长，本次不检查超出音频末尾的行。'),
        ],
        if (skipped > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote('另有 $skipped 行手动编辑过且时间有问题，已跳过；可在检查器里逐行校准。'),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          nothingFound
              ? '时间轴没有发现问题。'
              : '可自动修复 ${plan.fixes.length} 行，需要人工定点 '
                    '${plan.manualIssues.length} 行。',
          key: const ValueKey('timeline_repair_summary'),
          style: theme.textTheme.titleSmall,
        ),
        if (!nothingFound) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote(
            _remaining == 0
                ? '按当前勾选应用后，时间轴不再有冲突。'
                : '按当前勾选应用后，仍有 $_remaining 行存在时间冲突。',
            warning: _remaining > 0,
          ),
        ],
        if (plan.fixes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: Text('可自动修复', style: theme.textTheme.labelLarge)),
              TextButton(
                key: const ValueKey('timeline_repair_toggle_all'),
                onPressed: () => _update(() {
                  final selectAll = _selected.length != plan.fixes.length;
                  _selected.clear();
                  if (selectAll) {
                    _selected.addAll(
                      List.generate(plan.fixes.length, (i) => i),
                    );
                  }
                }),
                child: Text(
                  _selected.length == plan.fixes.length ? '全不选' : '全选',
                ),
              ),
            ],
          ),
          for (var position = 0; position < fixesShown; position++)
            _FixRow(
              key: ValueKey('timeline_fix_$position'),
              fix: plan.fixes[position],
              selected: _selected.contains(position),
              onSelectedChanged: (value) => _update(
                () => value
                    ? _selected.add(position)
                    : _selected.remove(position),
              ),
              onPreview: widget.onPreviewLine == null
                  ? null
                  : () => widget.onPreviewLine!(plan.fixes[position].index),
            ),
          if (plan.fixes.length > fixesShown)
            LyricBatchNote(
              '另有 ${plan.fixes.length - fixesShown} 行未列出，它们保持当前勾选状态。',
            ),
        ],
        if (plan.manualIssues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('需要人工定点', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          const LyricBatchNote(
            '这些问题无法从相邻行可靠推断。关闭后在列表中选中该行，'
            '播放到对应位置，用检查器里的“标记人声起点 / 终点”校准。',
          ),
          for (var position = 0; position < manualShown; position++)
            Padding(
              key: ValueKey('timeline_manual_$position'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                plan.manualIssues[position].message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
          if (plan.manualIssues.length > manualShown)
            LyricBatchNote(
              '另有 ${plan.manualIssues.length - manualShown} 行未列出。',
            ),
        ],
      ],
    );
  }
}

class _FixRow extends StatelessWidget {
  const _FixRow({
    super.key,
    required this.fix,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPreview,
  });

  final LyricTimelineFix fix;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final text = fix.before.text.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LyricBatchChangeRow(
            index: fix.index,
            before:
                '${LyricTimelineRepairStrings.span(fix.before)}'
                '${text.isEmpty ? '' : '  $text'}',
            after: LyricTimelineRepairStrings.span(fix.after),
            note: LyricTimelineRepairStrings.note(fix),
            selected: selected,
            onSelectedChanged: onSelectedChanged,
          ),
        ),
        if (onPreview != null)
          IconButton(
            tooltip: '试听第 ${fix.index + 1} 行',
            onPressed: onPreview,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
      ],
    );
  }
}
