import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/recognition_review_summary.dart';
import '../../domain/services/lyric_draft_health_service.dart';
import 'lyric_batch_text_edit.dart';

/// A compact post-recognition summary above the lyric list.
///
/// It answers "what did recognition produce and where do I start?" with plain
/// counts. A number the run did not collect is shown as "未采集"; nothing is
/// shown as a percentage or a confidence. The only action is entering the
/// existing review queue — smart proofreading keeps its single entry in the
/// toolbar.
class LyricRecognitionSummaryCard extends StatefulWidget {
  final RecognitionReviewSummary summary;

  /// Switches the list to the "needs review" queue and selects its first row.
  /// Null hides the button (for example while nothing is pending).
  final VoidCallback? onStartReview;

  /// Mechanical problems a batch tool can fix; null hides the hints.
  final LyricDraftHealth? health;

  /// Opens the batch tool a hint refers to. Null hides the hints.
  final ValueChanged<LyricBatchTextTool>? onOpenBatchTool;

  const LyricRecognitionSummaryCard({
    super.key,
    required this.summary,
    required this.onStartReview,
    this.health,
    this.onOpenBatchTool,
  });

  /// One hint per tool that has work to do, in the order worth doing it:
  /// deleting caption rows and recognition loops first (they would otherwise
  /// be split or unified),
  /// then fixing line structure, then unifying repeated lines, and timing
  /// last because the other tools change rows it would otherwise re-time.
  static List<({LyricBatchTextTool tool, String label, String tooltip})>
  healthHints(LyricDraftHealth health) => [
    if (health.captionRows > 0)
      (
        tool: LyricBatchTextTool.textCleanup,
        label: '字幕水印/标注 ${health.captionRows} 行',
        tooltip: '识别器在静音或伴奏处编造的“谢谢观看”、[音乐] 等行；打开“清理识别文本”预览后删除',
      ),
    if (health.loopRows > 0)
      (
        tool: LyricBatchTextTool.asrLoopCheck,
        label: '识别循环 ${health.loopRows} 行',
        tooltip: '识别器卡住时把一句反复输出十几遍，或连续多行完全相同；打开“识别循环检查”预览后删减',
      ),
    if (health.structureIssues > 0)
      (
        tool: LyricBatchTextTool.lineStructure,
        label: [
          if (health.longLines > 0) '过长 ${health.longLines} 行',
          if (health.fragments > 0) '碎片 ${health.fragments} 处',
        ].join(' · '),
        tooltip: '一行装了两句或一句被切碎；打开“整理断行”逐条确认拆分与合并',
      ),
    if (health.repetitionGroups > 0)
      (
        tool: LyricBatchTextTool.repetitionConsistency,
        label: '重复句写法不一 ${health.repetitionGroups} 组',
        tooltip: '同一句歌词在不同段落识别成不同写法；打开“重复段落一致性检查”统一',
      ),
    if (health.timelineRows > 0)
      (
        tool: LyricBatchTextTool.timelineRepair,
        label: '时间轴问题 ${health.timelineRows} 行',
        tooltip: '行与行重叠、结束早于开始或时间顺序颠倒；打开“检查时间轴”预览可自动修复的部分',
      ),
    if (health.paceRows > 0)
      (
        tool: LyricBatchTextTool.paceCheck,
        label: '语速异常 ${health.paceRows} 行',
        tooltip: '比全曲语速快得多或慢得多的行，多半结束被截断、跨过间奏或漏字多字；打开“语速异常检查”逐行试听',
      ),
    if (health.missedRepeatSpots > 0)
      (
        tool: LyricBatchTextTool.missedRepeatCheck,
        label: '可能漏唱的和声 ${health.missedRepeatSpots} 处',
        tooltip: '结尾反复的和声常被识别器缩短，逐字时间挤在一起或副歌后留下长空白；打开“漏唱和声检查”试听后补上',
      ),
    if (health.staleWordRows > 0)
      (
        tool: LyricBatchTextTool.wordTimingCheck,
        label: '逐字时间失效 ${health.staleWordRows} 行',
        tooltip: '改字后字数与逐字时间不再匹配，逐字导出会按字数估算；打开“逐字时间检查”清除或重新打轴',
      ),
  ];

  /// Short display name for an engine identity such as `qwen3-asr-1.7b`.
  static String engineLabel(String? engine) {
    if (engine == null) return '未知引擎';
    final lower = engine.toLowerCase();
    if (lower.contains('qwen')) return 'Qwen3-ASR';
    if (lower.contains('whisper')) return 'Whisper';
    return engine;
  }

  static String profileLabel(String? profile) => switch (profile) {
    null => '未采集',
    'whisper-lyrics-v2' => '歌词增强',
    // v1 sent a title/artist prompt with the text history on (before D-027).
    'whisper-lyrics-v1' => '歌词增强（旧版）',
    'whisper-standard-v1' => '标准参数',
    _ => profile,
  };

  static String countLabel(int? value) => value == null ? '未采集' : '$value';

  @override
  State<LyricRecognitionSummaryCard> createState() =>
      _LyricRecognitionSummaryCardState();
}

class _LyricRecognitionSummaryCardState
    extends State<LyricRecognitionSummaryCard> {
  // Collapsed by default: counts stay visible, the explanation is one tap
  // away. The card must not crowd the lyric rows it summarises.
  bool _expanded = false;

  String _engineLine(RecognitionReviewSummary summary) {
    final primary = LyricRecognitionSummaryCard.engineLabel(
      summary.primaryEngine,
    );
    if (summary.ranTwoEngines) {
      return '$primary + ${LyricRecognitionSummaryCard.engineLabel(summary.secondaryEngine)} 双引擎';
    }
    if (summary.degraded) return '$primary（第二引擎未参与）';
    return primary;
  }

  String? _whisperLine(RecognitionReviewSummary summary) {
    if (summary.whisperEffectiveProfile == null) {
      // Old projects and runs without Whisper have no profile record.
      return summary.primaryEngine?.toLowerCase().contains('whisper') == true ||
              summary.secondaryEngine?.toLowerCase().contains('whisper') == true
          ? 'Whisper 参数：未采集'
          : null;
    }
    final effective = LyricRecognitionSummaryCard.profileLabel(
      summary.whisperEffectiveProfile,
    );
    if (!summary.whisperProfileDegraded) return 'Whisper 参数：$effective';
    return 'Whisper 参数：$effective（运行时不支持歌词增强，已安全回退）';
  }

  List<Widget> _healthChips(
    LyricDraftHealth health,
    ValueChanged<LyricBatchTextTool> open,
  ) {
    final hints = LyricRecognitionSummaryCard.healthHints(health);
    if (hints.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        key: const ValueKey('lyric_recognition_summary_health'),
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '可批量整理：',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          for (final hint in hints)
            Tooltip(
              message: hint.tooltip,
              child: ActionChip(
                key: ValueKey('lyric_health_${hint.tool.name}'),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.auto_fix_normal_rounded, size: 16),
                label: Text(hint.label),
                onPressed: () => open(hint.tool),
              ),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final spec = AppResponsive.of(context);
    final theme = Theme.of(context);
    final whisperLine = _whisperLine(summary);
    final pending = summary.pendingReview;
    final metrics = <({String label, String value, bool attention})>[
      (label: '总行数', value: '${summary.totalLines}', attention: false),
      (
        label: '双引擎分歧',
        value: summary.ranTwoEngines
            ? LyricRecognitionSummaryCard.countLabel(summary.disagreementLines)
            : '不可用',
        attention: (summary.disagreementLines ?? 0) > 0,
      ),
      (
        label: '建议补入',
        value: summary.ranTwoEngines
            ? LyricRecognitionSummaryCard.countLabel(
                summary.pendingSecondaryOnlySuggestions,
              )
            : '不可用',
        attention: (summary.pendingSecondaryOnlySuggestions ?? 0) > 0,
      ),
      (label: '待复核', value: '$pending', attention: pending > 0),
    ];

    return Container(
      key: const ValueKey('lyric_recognition_summary_card'),
      margin: EdgeInsets.fromLTRB(
        spec.isCompact ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.xs,
        spec.isCompact ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '识别结果 · ${_engineLine(summary)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.onStartReview != null && pending > 0)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('lyric_recognition_summary_start'),
                    onPressed: widget.onStartReview,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(0, spec.minimumInteractiveExtent),
                    ),
                    icon: const Icon(Icons.playlist_play_rounded, size: 18),
                    label: Text(spec.isCompact ? '复核' : '开始复核 $pending 行'),
                  ),
                ),
              SizedBox(
                width: spec.minimumInteractiveExtent,
                height: spec.minimumInteractiveExtent,
                child: IconButton(
                  key: const ValueKey('lyric_recognition_summary_toggle'),
                  tooltip: _expanded ? '收起识别摘要' : '展开识别摘要',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final metric in metrics)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${metric.label}：',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      TextSpan(
                        text: metric.value,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: metric.attention
                              ? AppColors.warning
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (widget.health != null && widget.onOpenBatchTool != null)
            ..._healthChips(widget.health!, widget.onOpenBatchTool!),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                ?whisperLine,
                if ((summary.segmentationOnlySecondary ?? 0) > 0)
                  '另有 ${summary.segmentationOnlySecondary} 处仅分段不同，未重复插入',
                if (summary.ranTwoEngines)
                  '建议补入的行只有一个引擎听到，请试听后保留或删除；采用备选只替换文字，不改时间',
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
