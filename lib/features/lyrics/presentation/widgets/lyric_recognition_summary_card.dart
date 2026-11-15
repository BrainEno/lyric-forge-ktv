import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/recognition_review_summary.dart';

/// A compact post-recognition summary above the lyric list.
///
/// It answers "what did recognition produce and where do I start?" with plain
/// counts. A number the run did not collect is shown as "未采集"; nothing is
/// shown as a percentage or a confidence. The only action is entering the
/// existing review queue — Proofread V2 keeps its single entry in the toolbar.
class LyricRecognitionSummaryCard extends StatefulWidget {
  final RecognitionReviewSummary summary;

  /// Switches the list to the "needs review" queue and selects its first row.
  /// Null hides the button (for example while nothing is pending).
  final VoidCallback? onStartReview;

  const LyricRecognitionSummaryCard({
    super.key,
    required this.summary,
    required this.onStartReview,
  });

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
    'whisper-lyrics-v1' => '歌词增强',
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
