import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_missed_repeat_detector.dart';
import 'lyric_batch_text_edit.dart';

/// Plays a stretch of the song for a finding about row [index].
typedef LyricSpanPreview =
    void Function(int index, Duration start, Duration end);

/// User-facing text of the missed-repeat check.
class LyricMissedRepeatStrings {
  const LyricMissedRepeatStrings._();

  static const String actionTitle = '漏唱和声检查';
  static const String actionDetail = '找出结尾反复的和声、口号被识别器缩短的地方：逐字时间挤在一起，或和声后留下长空白';
  static const String intro =
      '识别器听到同一句和声反复很多遍时，往往只写一两遍，对齐器又对不上多出来的歌声。'
      '留下的痕迹有三种：许多字挤在同一时刻；一个字被拉长到六秒以上，盖住了没识别出的歌声或前奏；'
      '和声或副歌之后留下一大段没有歌词的空白。'
      '挤在一起的逐字时间默认清除（导出时按字数均分）；行首被拉长的字默认缩短，这一行的开始时间随之后移。'
      '行尾被拉长的字也可能是长音，行中被拉长的字说明中间漏了歌词，都请先试听。'
      '长空白确实还在唱时，再勾选插入重复行，可以调整插入几行；插入后建议用“打轴”校准时间。'
      '漏掉的歌词也可以选中空白前后的行，用“重新识别这一段”（延伸到相邻行）找回。'
      '手动编辑过的行不修改。结果可撤销，保存后才写盘。';

  static String applied(int cleared, int retimed, int inserted) {
    final parts = [
      if (cleared > 0) '已清除 $cleared 行挤在一起的逐字时间',
      if (retimed > 0) '已修正 $retimed 处被拉长的字',
      if (inserted > 0) '已插入 $inserted 行重复和声',
    ];
    return '${parts.join('，')}（未写入磁盘）';
  }

  static String reasonLabel(LyricChantReason? reason) => switch (reason) {
    LyricChantReason.vocables => '拟声和声',
    LyricChantReason.selfRepeat => '行内反复',
    LyricChantReason.refrain => '反复出现的句子',
    null => '和声',
  };

  static String note(LyricMissedRepeatIssue issue) {
    switch (issue.kind) {
      case LyricMissedRepeatKind.crowdedWords:
        return [
          '${issue.crowdedCount} 个字挤在 ${clock(issue.crowdedAt)} 同一时刻',
          if (issue.crowdedAtStart) '这一行的开始时间可能偏早',
          if (issue.protected) '手动编辑过，不修改',
        ].join('，');
      case LyricMissedRepeatKind.stretchedWord:
        final word = issue.wordText.trim().isEmpty
            ? '一个字'
            : '“${issue.wordText.trim()}”';
        return [
          '$word 从 ${clock(issue.spanStart)} 拉长到 ${clock(issue.spanEnd)}'
              '（${seconds(issue.span)} 秒）',
          switch (issue.position) {
            LyricStretchedWordPosition.first =>
              issue.proposedStart == null
                  ? '这一行的开始时间可能偏早'
                  : '这一行可能开始得太早，建议从 ${clock(issue.proposedStart!)} 开始',
            LyricStretchedWordPosition.last =>
              issue.proposedEnd == null
                  ? '这一行的结束时间可能偏晚'
                  : '可能是长音，也可能结束太晚；缩短则在 ${clock(issue.proposedEnd!)} 结束',
            _ => '这里可能漏了歌词，常见于反复的和声',
          },
          if (issue.protected) '手动编辑过，不修改',
        ].join('，');
      case LyricMissedRepeatKind.gapAfterChant:
        return [
          '${reasonLabel(issue.reason)}之后 '
              '${clock(issue.spanStart)}–${clock(issue.spanEnd)} '
              '有 ${seconds(issue.span)} 秒'
              '${issue.toAudioEnd ? '到歌曲结束' : ''}没有歌词',
          if (issue.resumes) '空白之后同一句又出现',
          if (issue.fill.isEmpty) '这一行没有可用的时长，无法插入',
        ].join('，');
    }
  }

  static String kindLabel(LyricMissedRepeatKind kind) => switch (kind) {
    LyricMissedRepeatKind.crowdedWords => '逐字时间挤在一起',
    LyricMissedRepeatKind.stretchedWord => '字被拉长',
    LyricMissedRepeatKind.gapAfterChant => '这里可能漏了重复的和声',
  };

  static String seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(1);

  static String clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inMilliseconds % 60000) / 1000;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }
}

/// Shows the missed-repeat check. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricMissedRepeatDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  Duration? audioDuration,
  ValueChanged<int>? onPreviewLine,
  LyricSpanPreview? onPreviewSpan,
  LyricMissedRepeatDetector detector = const LyricMissedRepeatDetector(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricMissedRepeatDialog(
      document: document,
      protectedIndices: protectedIndices,
      audioDuration: audioDuration,
      onPreviewLine: onPreviewLine,
      onPreviewSpan: onPreviewSpan,
      detector: detector,
    ),
  );
}

/// Lists crowded word timing and gaps after chants; the selected fixes are
/// applied as one undoable change.
class LyricMissedRepeatDialog extends StatefulWidget {
  const LyricMissedRepeatDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.audioDuration,
    this.onPreviewLine,
    this.onPreviewSpan,
    this.detector = const LyricMissedRepeatDetector(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final Duration? audioDuration;
  final ValueChanged<int>? onPreviewLine;
  final LyricSpanPreview? onPreviewSpan;
  final LyricMissedRepeatDetector detector;

  /// How many findings the preview lists.
  static const int previewLimit = 60;

  @override
  State<LyricMissedRepeatDialog> createState() =>
      _LyricMissedRepeatDialogState();
}

class _LyricMissedRepeatDialogState extends State<LyricMissedRepeatDialog> {
  late final LyricMissedRepeatPlan _plan = widget.detector.plan(
    widget.document,
    protectedIndices: widget.protectedIndices,
    audioDuration: widget.audioDuration,
  );
  late final Set<int> _selected = _plan.defaultPositions.toSet();
  final Map<int, int> _fillCounts = {};

  void _confirm() {
    if (_selected.isEmpty) return;
    final counts = _plan.countFor(_selected, fillCounts: _fillCounts);
    final document = _plan.applyTo(
      widget.document,
      _selected,
      fillCounts: _fillCounts,
    );
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: document,
        label: LyricMissedRepeatStrings.actionTitle,
        message: LyricMissedRepeatStrings.applied(
          counts.cleared,
          counts.retimed,
          counts.inserted,
        ),
        selectedLineIndex: _plan.selectionAfterApply(_selected),
      ),
    );
  }

  /// Changing how many copies to insert is a decision to insert them, so it
  /// also ticks the finding; zero copies unticks it.
  void _setFill(int position, int count) => setState(() {
    _fillCounts[position] = count;
    if (count == 0) {
      _selected.remove(position);
    } else {
      _selected.add(position);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final counts = plan.countFor(_selected, fillCounts: _fillCounts);
    int countOf(LyricMissedRepeatKind kind) =>
        plan.issues.where((issue) => issue.kind == kind).length;
    final crowded = countOf(LyricMissedRepeatKind.crowdedWords);
    final stretched = countOf(LyricMissedRepeatKind.stretchedWord);
    final gaps = countOf(LyricMissedRepeatKind.gapAfterChant);
    final shown = plan.issues.length < LyricMissedRepeatDialog.previewLimit
        ? plan.issues.length
        : LyricMissedRepeatDialog.previewLimit;
    final nothingSelected =
        counts.cleared == 0 && counts.retimed == 0 && counts.inserted == 0;

    return LyricBatchEditDialogFrame(
      title: LyricMissedRepeatStrings.actionTitle,
      confirmKey: const ValueKey('missed_repeat_confirm'),
      confirmIcon: Icons.playlist_add_rounded,
      confirmLabel: nothingSelected
          ? (plan.fixablePositions.isEmpty ? '没有可自动处理的项' : '请选择要处理的项')
          : [
              if (counts.cleared > 0) '清除 ${counts.cleared} 行逐字时间',
              if (counts.retimed > 0) '修正 ${counts.retimed} 处拉长',
              if (counts.inserted > 0) '插入 ${counts.inserted} 行',
            ].join('，'),
      onConfirm: nothingSelected ? null : _confirm,
      children: [
        const LyricBatchNote(LyricMissedRepeatStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        Text(
          plan.issues.isEmpty
              ? '没有发现可能漏唱的和声。'
              : '${[if (crowded > 0) '逐字时间挤在一起 $crowded 行', if (stretched > 0) '字被拉长 $stretched 处', if (gaps > 0) '和声后长空白 $gaps 处'].join('，')}；默认勾选 ${plan.defaultPositions.length} 项。',
          key: const ValueKey('missed_repeat_summary'),
          style: theme.textTheme.titleSmall,
        ),
        if (widget.audioDuration == null && plan.issues.isNotEmpty)
          const LyricBatchNote('本工程没有音频时长，最后一行之后的空白无法检查。'),
        for (var position = 0; position < shown; position++)
          _MissedRepeatRow(
            key: ValueKey('missed_repeat_issue_$position'),
            issue: plan.issues[position],
            line: widget.document.lines[plan.issues[position].index],
            fillCount: plan.fillCountFor(position, _fillCounts),
            selected: _selected.contains(position),
            onSelectedChanged: plan.issues[position].fixable
                ? (value) => setState(
                    () => value
                        ? _selected.add(position)
                        : _selected.remove(position),
                  )
                : null,
            onFillChanged: plan.issues[position].fill.isEmpty
                ? null
                : (count) => _setFill(position, count),
            onPreviewLine: widget.onPreviewLine == null
                ? null
                : () => widget.onPreviewLine!(plan.issues[position].index),
            onPreviewSpan:
                widget.onPreviewSpan == null ||
                    plan.issues[position].span <= Duration.zero
                ? null
                : () => widget.onPreviewSpan!(
                    plan.issues[position].index,
                    plan.issues[position].spanStart,
                    plan.issues[position].spanEnd,
                  ),
          ),
        if (plan.issues.length > shown)
          LyricBatchNote('另有 ${plan.issues.length - shown} 项未列出，它们保持当前勾选状态。'),
      ],
    );
  }
}

class _MissedRepeatRow extends StatelessWidget {
  const _MissedRepeatRow({
    super.key,
    required this.issue,
    required this.line,
    required this.fillCount,
    required this.selected,
    required this.onSelectedChanged,
    required this.onFillChanged,
    required this.onPreviewLine,
    required this.onPreviewSpan,
  });

  final LyricMissedRepeatIssue issue;
  final LyricLine line;
  final int fillCount;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final ValueChanged<int>? onFillChanged;
  final VoidCallback? onPreviewLine;
  final VoidCallback? onPreviewSpan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onSelectedChanged != null;
    final textColor = enabled ? null : AppColors.textSecondary;
    final isGap = issue.kind == LyricMissedRepeatKind.gapAfterChant;
    final fillChanged = onFillChanged;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: enabled && selected,
            onChanged: enabled
                ? (value) => onSelectedChanged!(value ?? false)
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${issue.index + 1} 行 · '
                  '${LyricMissedRepeatStrings.kindLabel(issue.kind)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  line.text.trim().isEmpty ? '（空行）' : line.text.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
                Text(
                  LyricMissedRepeatStrings.note(issue),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (isGap && fillChanged != null)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '插入 $fillCount 行（最多 ${issue.fill.length} 行）',
                          key: ValueKey('missed_repeat_fill_${issue.index}'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '少插一行',
                        visualDensity: VisualDensity.compact,
                        onPressed: fillCount > 0
                            ? () => fillChanged(fillCount - 1)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                      ),
                      IconButton(
                        tooltip: '多插一行',
                        visualDensity: VisualDensity.compact,
                        onPressed: fillCount < issue.fill.length
                            ? () => fillChanged(fillCount + 1)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onPreviewLine != null)
            IconButton(
              tooltip: '试听第 ${issue.index + 1} 行',
              onPressed: onPreviewLine,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (onPreviewSpan != null)
            IconButton(
              tooltip: switch (issue.kind) {
                LyricMissedRepeatKind.gapAfterChant =>
                  '试听第 ${issue.index + 1} 行之后的空白',
                LyricMissedRepeatKind.stretchedWord => '试听被拉长的这一段',
                LyricMissedRepeatKind.crowdedWords => '试听挤在一起的这一段',
              },
              onPressed: onPreviewSpan,
              icon: const Icon(Icons.hearing_rounded),
            ),
        ],
      ),
    );
  }
}
