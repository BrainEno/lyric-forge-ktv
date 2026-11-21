import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_timing_shift_service.dart';
import '../../domain/services/lyric_word_timing_auditor.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the word timing check.
class LyricWordTimingCheckStrings {
  const LyricWordTimingCheckStrings._();

  static const String actionTitle = '逐字时间检查';
  static const String actionDetail = '导出卡拉 OK 逐字歌词前，找出逐字时间错位或挤成一团的行';
  static const String intro =
      '逐字时间来自识别、导入的卡拉 OK 文件、逐字打轴或逐字微调。'
      '改字后字数不再匹配的行，导出会忽略它的逐字时间，可以清除；'
      '行时间改过的行，逐字时间正按比例映射，可以把映射结果保存下来。'
      '这两项不改变导出结果，默认勾选。'
      '拖得过长、挤成一团或中间停顿很长的行只列出，请试听后用逐字微调或逐字打轴修正，或在停顿处拆分。'
      '歌词文字和行时间不会改变；结果可撤销，保存后才写盘。';

  static String applied(int rows) => '已整理 $rows 行的逐字时间（未写入磁盘）';

  static String seconds(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(1)} 秒';

  static String note(LyricWordTimingIssue issue) => switch (issue.kind) {
    LyricWordTimingIssueKind.stale => '文字改过，字数与逐字时间不再匹配，导出时按字数估算；建议清除',
    LyricWordTimingIssueKind.drifted =>
      '行时间改过，逐字时间（原 ${span(issue.recordedStart!, issue.recordedEnd!)}）'
          '正按比例映射到本行；建议保存映射结果',
    LyricWordTimingIssueKind.longWord =>
      '「${issue.word}」拖了 ${seconds(issue.duration!)}：长音，或把停顿算进了这个字',
    LyricWordTimingIssueKind.shortWords => '${issue.count} 个字不足 40 毫秒，多半是对齐跟丢了',
    LyricWordTimingIssueKind.innerGap =>
      '「${issue.word}」之前停了 ${seconds(issue.duration!)}，可能应在这里拆成两行',
  };

  static String span(Duration start, Duration end) =>
      '${formatLyricTimeInput(start)} → ${formatLyricTimeInput(end)}';
}

/// Shows the word timing check. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricWordTimingCheckDialog(
  BuildContext context, {
  required LyricDocument document,
  ValueChanged<int>? onPreviewLine,
  LyricWordTimingAuditor auditor = const LyricWordTimingAuditor(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricWordTimingCheckDialog(
      document: document,
      onPreviewLine: onPreviewLine,
      auditor: auditor,
    ),
  );
}

class LyricWordTimingCheckDialog extends StatefulWidget {
  const LyricWordTimingCheckDialog({
    super.key,
    required this.document,
    this.onPreviewLine,
    this.auditor = const LyricWordTimingAuditor(),
  });

  final LyricDocument document;
  final ValueChanged<int>? onPreviewLine;
  final LyricWordTimingAuditor auditor;

  /// How many findings the preview lists.
  static const int previewLimit = 80;

  @override
  State<LyricWordTimingCheckDialog> createState() =>
      _LyricWordTimingCheckDialogState();
}

class _LyricWordTimingCheckDialogState
    extends State<LyricWordTimingCheckDialog> {
  late final LyricWordTimingPlan _plan = widget.auditor.plan(widget.document);
  late final Set<int> _selected = _plan.fixablePositions.toSet();

  void _confirm() {
    if (_selected.isEmpty) return;
    final first = _selected
        .map((position) => _plan.issues[position].index)
        .reduce((a, b) => a < b ? a : b);
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: _plan.applyTo(widget.document, _selected),
        label: LyricWordTimingCheckStrings.actionTitle,
        message: LyricWordTimingCheckStrings.applied(_selected.length),
        selectedLineIndex: first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final fixable = plan.fixablePositions;
    final shown = plan.issues.length < LyricWordTimingCheckDialog.previewLimit
        ? plan.issues.length
        : LyricWordTimingCheckDialog.previewLimit;
    final untimed = plan.sungRows - plan.timedRows;

    String count(LyricWordTimingIssueKind kind, String label) {
      final value = plan.countOf(kind);
      return value == 0 ? '' : '$label $value 行';
    }

    final breakdown = [
      count(LyricWordTimingIssueKind.stale, '失效'),
      count(LyricWordTimingIssueKind.drifted, '已映射'),
      count(LyricWordTimingIssueKind.longWord, '拖长'),
      count(LyricWordTimingIssueKind.shortWords, '过短'),
      count(LyricWordTimingIssueKind.innerGap, '长停顿'),
    ].where((part) => part.isNotEmpty).join('，');

    return LyricBatchEditDialogFrame(
      title: LyricWordTimingCheckStrings.actionTitle,
      confirmKey: const ValueKey('word_check_confirm'),
      confirmIcon: Icons.fact_check_outlined,
      confirmLabel: _selected.isEmpty
          ? (fixable.isEmpty ? '没有需要整理的行' : '请选择要整理的行')
          : '整理 ${_selected.length} 行',
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricWordTimingCheckStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${plan.timedRows} 行有可用的逐字时间，'
          '$untimed 行导出时按字数估算（共 ${plan.sungRows} 行有演唱文字）。',
          key: const ValueKey('word_check_coverage'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          plan.issues.isEmpty ? '没有发现问题。' : breakdown,
          key: const ValueKey('word_check_summary'),
          style: theme.textTheme.bodyMedium,
        ),
        if (plan.timedRows == 0 && plan.issues.isEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          const LyricBatchNote(
            '本工程还没有逐字时间。可以用「逐字打轴」边听边按，'
            '或在检查器里对单行做逐字微调。',
          ),
        ],
        if (fixable.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('word_check_toggle_all'),
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
          _WordTimingIssueRow(
            key: ValueKey('word_check_issue_$position'),
            issue: plan.issues[position],
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

class _WordTimingIssueRow extends StatelessWidget {
  const _WordTimingIssueRow({
    super.key,
    required this.issue,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPreview,
  });

  final LyricWordTimingIssue issue;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = issue.line;
    final text = line.text.trim();
    final note = LyricWordTimingCheckStrings.note(issue);
    final fixable = issue.fixable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: fixable
                ? Checkbox(
                    value: selected,
                    onChanged: onSelectedChanged == null
                        ? null
                        : (value) => onSelectedChanged!(value ?? false),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Icon(
                      Icons.hearing_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${issue.index + 1} 行 · '
                    '${LyricWordTimingCheckStrings.span(line.startTime, line.endTime)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(text.isEmpty ? '（空行）' : text),
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fixable
                          ? AppColors.textSecondary
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onPreview != null)
            IconButton(
              tooltip: '试听第 ${issue.index + 1} 行',
              onPressed: onPreview,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
        ],
      ),
    );
  }
}
