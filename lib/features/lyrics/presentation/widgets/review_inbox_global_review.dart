import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../controllers/review_inbox_bulk_review.dart';

/// Sentences of the inbox-wide 全部工程标为已复核 (audit R-03).
abstract final class ReviewInboxGlobalReviewText {
  static const String buttonLabel = '全部工程标为已复核';
  static const String confirmLabel = '全部标为已复核';
  static const String cancelLabel = '取消';
  static const String undoLabel = '撤销';
  static const String nothingToMark = '每个工程的每一行都已确认';

  /// How many project names the confirmation lists before "等 N 个".
  static const int namePreviewCount = 3;

  static String title(int projects) => '把 $projects 个工程全部标为已复核？';

  static String summary({
    required int projects,
    required int totalLines,
    required int pendingLines,
  }) {
    final confirmed = '这 $projects 个工程共 $totalLines 行都会记为人工确认，';
    return '$confirmed待复核的 $pendingLines 行会离开队列。';
  }

  static const String reversibleNote = '之后改动任何一行的文字或时间，那一行会重新回到待复核。完成后可以撤销。';

  /// 「甲」「乙」「丙」等 5 个工程 — or every name when there are few.
  static String names(List<String> names) {
    final shown = names.take(namePreviewCount).map((name) => '「$name」');
    final joined = shown.join('');
    return names.length > namePreviewCount
        ? '$joined等 ${names.length} 个工程'
        : joined;
  }

  static String progress(int done, int total) => '正在标记第 $done/$total 个工程…';

  static String result(BulkReviewBatchResult batch) {
    final parts = <String>[
      if (batch.saved.isNotEmpty)
        '已将 ${batch.saved.length} 个工程标为已复核（新确认 ${batch.markedLines} 行）',
      if (batch.conflicts.isNotEmpty)
        '${batch.conflicts.length} 个工程刚在别处保存过，已跳过并重新读取，请再试一次',
      if (batch.failed.isNotEmpty) '${batch.failed.length} 个工程没能保存，请稍后再试',
    ];
    return parts.isEmpty ? nothingToMark : parts.join('；');
  }

  static String undoResult(BulkReviewBatchUndo undo) {
    if (undo.isComplete) {
      return '已撤销，${undo.restored} 个工程的复核标记恢复原样';
    }
    return [
      '已撤销 ${undo.restored} 个工程',
      if (undo.conflicts > 0) '${undo.conflicts} 个工程已有新的改动，没有撤销',
      if (undo.failed > 0) '${undo.failed} 个工程没能恢复，请稍后再试',
    ].join('；');
  }
}

/// Progress of a running inbox-wide review.
typedef ReviewInboxGlobalProgress = ({int done, int total});

/// The inbox summary line with the global 全部工程标为已复核 button, or the
/// progress of that action while it runs.
///
/// Before this, confirming everything meant opening each project's 更多操作
/// menu in turn; the per-project action stays for the one song the user has
/// checked.
class ReviewInboxSummaryBar extends StatelessWidget {
  const ReviewInboxSummaryBar({
    super.key,
    required this.summary,
    required this.onMarkEverything,
    this.progress,
  });

  final String summary;

  /// Null hides the button: nothing waits for review.
  final VoidCallback? onMarkEverything;

  /// Non-null while the global action runs; replaces the button.
  final ReviewInboxGlobalProgress? progress;

  static const Key buttonKey = ValueKey('review-inbox:mark-everything');
  static const Key progressKey = ValueKey(
    'review-inbox:mark-everything-progress',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = progress;
    final summaryText = Text(
      summary,
      style: theme.textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
    if (running != null) {
      final fraction = running.total == 0 ? null : running.done / running.total;
      return Padding(
        key: progressKey,
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            summaryText,
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                ReviewInboxGlobalReviewText.progress(
                  running.done,
                  running.total,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                color: AppColors.accent,
                backgroundColor: AppColors.bgHighlight,
              ),
            ),
          ],
        ),
      );
    }
    final onPressed = onMarkEverything;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          summaryText,
          if (onPressed != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: AppResponsive.of(context).minimumInteractiveExtent,
              ),
              child: TextButton.icon(
                key: buttonKey,
                onPressed: onPressed,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text(ReviewInboxGlobalReviewText.buttonLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// Confirms 全部工程标为已复核 with what it changes.
class ReviewInboxGlobalReviewDialog extends StatelessWidget {
  const ReviewInboxGlobalReviewDialog({
    super.key,
    required this.projectNames,
    required this.totalLines,
    required this.pendingLines,
  });

  final List<String> projectNames;
  final int totalLines;
  final int pendingLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return AlertDialog(
      title: Text(ReviewInboxGlobalReviewText.title(projectNames.length)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ReviewInboxGlobalReviewText.summary(
              projects: projectNames.length,
              totalLines: totalLines,
              pendingLines: pendingLines,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            ReviewInboxGlobalReviewText.names(projectNames),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(ReviewInboxGlobalReviewText.reversibleNote, style: secondary),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(ReviewInboxGlobalReviewText.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(ReviewInboxGlobalReviewText.confirmLabel),
        ),
      ],
    );
  }
}
