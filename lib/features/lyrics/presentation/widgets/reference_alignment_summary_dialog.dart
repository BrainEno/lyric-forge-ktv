import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/reference_alignment_applier.dart';

class ReferenceAlignmentDecision {
  final bool applyReferenceTiming;

  const ReferenceAlignmentDecision({required this.applyReferenceTiming});
}

Future<ReferenceAlignmentDecision?> showReferenceAlignmentSummaryDialog(
  BuildContext context, {
  required ReferenceAlignmentApplyResult preview,
  required bool isTimedReference,
  required bool canApplyReferenceTiming,
  required String? timingUnavailableReason,
  required int timedLineCount,
  required int referenceLineCount,
  required double minimumSimilarity,
  required int documentLineCount,
}) {
  return showDialog<ReferenceAlignmentDecision>(
    context: context,
    builder: (_) => _ReferenceAlignmentSummaryDialog(
      preview: preview,
      isTimedReference: isTimedReference,
      canApplyReferenceTiming: canApplyReferenceTiming,
      timingUnavailableReason: timingUnavailableReason,
      timedLineCount: timedLineCount,
      referenceLineCount: referenceLineCount,
      minimumSimilarity: minimumSimilarity,
      documentLineCount: documentLineCount,
    ),
  );
}

class _ReferenceAlignmentSummaryDialog extends StatefulWidget {
  final ReferenceAlignmentApplyResult preview;
  final bool isTimedReference;
  final bool canApplyReferenceTiming;
  final String? timingUnavailableReason;
  final int timedLineCount;
  final int referenceLineCount;
  final double minimumSimilarity;
  final int documentLineCount;

  const _ReferenceAlignmentSummaryDialog({
    required this.preview,
    required this.isTimedReference,
    required this.canApplyReferenceTiming,
    required this.timingUnavailableReason,
    required this.timedLineCount,
    required this.referenceLineCount,
    required this.minimumSimilarity,
    required this.documentLineCount,
  });

  @override
  State<_ReferenceAlignmentSummaryDialog> createState() =>
      _ReferenceAlignmentSummaryDialogState();
}

class _ReferenceAlignmentSummaryDialogState
    extends State<_ReferenceAlignmentSummaryDialog> {
  late bool _applyTiming;

  @override
  void initState() {
    super.initState();
    _applyTiming = widget.canApplyReferenceTiming && widget.timedLineCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final preview = widget.preview;
    final threshold = (widget.minimumSimilarity * 100).round();
    final applyTiming = _applyTiming && widget.canApplyReferenceTiming;
    final canApply = preview.hasChanges || applyTiming;

    final correctionsToShow = preview.corrections.take(5).toList();
    final remainingCorrections =
        preview.corrections.length - correctionsToShow.length;
    final maxWidth = spec.isCompact ? 560.0 : 620.0;
    final maxHeight =
        (media.size.height -
                media.viewInsets.bottom -
                spec.pageGutter * 2 -
                120)
            .clamp(240.0, 680.0)
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('对齐结果'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '参考歌词 ${widget.referenceLineCount} 行'
            ' / 当前草稿 ${widget.documentLineCount} 行',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _SummaryMetric(
                    label: '可纠正',
                    count: preview.correctableCount,
                    color: AppColors.accent,
                  ),
                  _SummaryMetric(label: '完全一致', count: preview.identicalCount),
                  _SummaryMetric(
                    label: '低相似',
                    count: preview.skippedLowConfidenceIndices.length,
                    color: AppColors.warning,
                  ),
                  _SummaryMetric(
                    label: '手动跳过',
                    count: preview.skippedManuallyEditedIndices.length,
                    color: AppColors.warning,
                  ),
                  _SummaryMetric(
                    label: '参考漏行',
                    count: preview.missingReferenceCount,
                    color: AppColors.warning,
                  ),
                  _SummaryMetric(
                    label: '多余识别',
                    count: preview.unmatchedAsrCount,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (correctionsToShow.isEmpty)
                _NoteBox(
                  icon: Icons.check_circle_outline_rounded,
                  text: preview.hasChanges
                      ? '没有可纠正的文字行。'
                      : '没有达到 $threshold% 相似度的可纠正行；可调整参考歌词后重试。',
                )
              else ...[
                Text(
                  '将纠正（相似度 ≥ $threshold%）',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final correction in correctionsToShow)
                  _CorrectionPreview(correction: correction),
                if (remainingCorrections > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '还有 $remainingCorrections 行…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
              if (preview.skippedManuallyEditedIndices.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.edit_note_rounded,
                  text:
                      '有 ${preview.skippedManuallyEditedIndices.length} 行是本次手动编辑过的，已自动跳过；如确需覆盖，可在逐行确认中单独处理。',
                ),
              ],
              if (preview.missingReferenceCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.playlist_add_rounded,
                  text:
                      '参考歌词中有 ${preview.missingReferenceCount} 行在 ASR 里找不到，不会自动插入；可先用编辑器里的“在播放位置插入”补行。',
                ),
              ],
              if (preview.unmatchedAsrCount > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                _NoteBox(
                  icon: Icons.help_outline_rounded,
                  text: '当前草稿有 ${preview.unmatchedAsrCount} 行没有参考对应，将保持原样。',
                ),
              ],
              if (widget.isTimedReference) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                if (widget.canApplyReferenceTiming)
                  CheckboxListTile(
                    value: _applyTiming,
                    onChanged: (value) {
                      setState(() => _applyTiming = value ?? false);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同时采用参考歌词时间轴'),
                    subtitle: Text('最多 ${widget.timedLineCount} 行；应用后全局偏移归零。'),
                  )
                else
                  _NoteBox(
                    icon: Icons.info_outline_rounded,
                    text:
                        widget.timingUnavailableReason ??
                        '参考歌词带时间戳，但当前无法整体替换时间轴；'
                            '本次只纠正文字并保留原时间轴。',
                  ),
              ] else ...[
                const SizedBox(height: AppSpacing.md),
                _NoteBox(
                  icon: Icons.schedule_rounded,
                  text: '纯文本参考：只纠正文字，保留 ASR 时间轴。',
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          child: Text(canApply ? '取消' : '关闭'),
        ),
        if (canApply)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              ReferenceAlignmentDecision(applyReferenceTiming: applyTiming),
            ),
            style: FilledButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            icon: const Icon(Icons.done_all_rounded),
            label: Text(_applyLabel(applyTiming)),
          ),
      ],
    );
  }

  String _applyLabel(bool applyTiming) {
    final textCount = widget.preview.correctableCount;
    if (textCount > 0 && applyTiming) {
      return '应用 $textCount 行修正 + 时间轴';
    }
    if (textCount > 0) return '应用 $textCount 行修正';
    return '采用参考时间轴';
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;

  const _SummaryMetric({required this.label, required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrectionPreview extends StatelessWidget {
  final AppliedReferenceCorrection correction;

  const _CorrectionPreview({required this.correction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${correction.asrLineIndex + 1} 行',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                '${(correction.similarity * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            correction.previousText.isEmpty ? '（空）' : correction.previousText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            correction.newText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoteBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
