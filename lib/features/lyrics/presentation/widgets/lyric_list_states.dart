import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_empty_state.dart';

// What the editor's line list shows around and instead of its rows: the
// search field, the candidate summary, and the three empty states. They were
// private classes and a private builder method at the end of the 1424-line
// lyric_list_pane.dart.

/// The action that clears the filter, or nothing when the host cannot.
List<Widget> _showAllActions(VoidCallback? onShowAllLines) => [
  if (onShowAllLines != null)
    OutlinedButton.icon(
      key: const ValueKey('lyric-list:show-all'),
      onPressed: onShowAllLines,
      icon: const Icon(Icons.format_list_bulleted_rounded),
      label: const Text(LyricListStateText.showAll),
    ),
];

/// The words of the list's states.
abstract final class LyricListStateText {
  static const String showAll = '显示全部歌词';
  static const String searchHint = '搜索歌词文本、时间或行号…';
  static const String clearSearch = '清除搜索';
  static const String noMatch = '没有匹配的歌词行';
  static const String filteredTitle = '当前筛选下没有待处理歌词';
  static const String filteredMessage = '换一个筛选条件，或回到全部歌词继续校对。';
  static const String queueDoneTitle = '本轮复核已完成';
  static const String queueQuietTitle = '暂未发现明显风险行';
  static const String queueQuietMessage =
      '当前没有达到复核阈值的明显问题。自动排序只看结构与时间轴证据，不能判断歌词语义是否正确，仍可结合试听和个人听感检查。';

  /// After [reviewedCount] rows were confirmed.
  static String queueDoneMessage(int reviewedCount) =>
      '已确认 $reviewedCount 行。若修改了歌词文本或时间轴，该行会自动重新进入待复核队列。请保存以保留确认记录。';

  /// The list shows a search field from this many lines.
  static const int searchFromLines = 9;
}

/// The review queue has nothing left: either everything was confirmed, or
/// nothing reached the review threshold.
class LyricReviewQueueEmptyState extends StatelessWidget {
  final int reviewedCount;
  final VoidCallback? onShowAllLines;

  const LyricReviewQueueEmptyState({
    super.key,
    required this.reviewedCount,
    this.onShowAllLines,
  });

  @override
  Widget build(BuildContext context) {
    final completed = reviewedCount > 0;
    return AppEmptyState(
      icon: Icons.check_circle_outline_rounded,
      iconColor: AppColors.accent,
      title: completed
          ? LyricListStateText.queueDoneTitle
          : LyricListStateText.queueQuietTitle,
      message: completed
          ? LyricListStateText.queueDoneMessage(reviewedCount)
          : LyricListStateText.queueQuietMessage,
      actions: _showAllActions(onShowAllLines),
    );
  }
}

/// Another filter hides every line.
class LyricFilteredEmptyState extends StatelessWidget {
  final VoidCallback? onShowAllLines;

  const LyricFilteredEmptyState({super.key, this.onShowAllLines});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.task_alt_rounded,
      iconColor: AppColors.accent,
      title: LyricListStateText.filteredTitle,
      message: LyricListStateText.filteredMessage,
      actions: _showAllActions(onShowAllLines),
    );
  }
}

/// The search matched no row.
class LyricSearchEmptyState extends StatelessWidget {
  const LyricSearchEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 42,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: 8),
          Text(LyricListStateText.noMatch),
        ],
      ),
    );
  }
}

/// The search field above the rows, with a clear button once it has text.
class LyricListSearchField extends StatelessWidget {
  const LyricListSearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    this.focusNode,
    this.padding = 0,
  });

  final TextEditingController controller;

  /// What is typed; the clear button shows while it is not empty.
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Lets Ctrl/Cmd + F in the list focus the field.
  final FocusNode? focusNode;

  /// The list's side padding.
  final double padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: LyricListStateText.searchHint,
          hintStyle: textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: LyricListStateText.clearSearch,
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          filled: true,
          fillColor: AppColors.bgSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        style: textTheme.bodyMedium,
      ),
    );
  }
}

/// The line about saved engine candidates above the rows.
class LyricCandidateSummary extends StatelessWidget {
  const LyricCandidateSummary({
    super.key,
    required this.text,
    this.padding = 0,
  });

  final String text;

  /// The list's side padding.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
