import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_loading_state.dart';

// Error, loading and empty states shared by the phone's remote library
// screens (songs, artists, albums) and its download manager.
//
// Each of those screens drew its own red line of text, bare spinner and
// grey "没有匹配…" sentence. The red text failed contrast, the spinner said
// nothing about what was loading, and the empty sentence was the same
// whether the desktop library was empty, a filter hid everything or a
// search matched nothing, with no way back to the full list. These widgets
// give the three screens one look built on the app's state widgets, and
// an empty result that says why it is empty and offers the way out.

/// Sentences of the transfer list states, shared by the screens and tests.
abstract final class TransferListText {
  static const String libraryLoading = '正在读取桌面音乐库…';
  static const String libraryEmptyTitle = '桌面音乐库里还没有歌曲';
  static const String libraryEmptyMessage =
      '在电脑上把歌曲导入 Elysium Player 后，下拉刷新即可看到。';
  static const String downloadedFilterTitle = '还没有下载到这台设备的歌曲';
  static const String lyricsFilterTitle = '没有带歌词的歌曲';
  static const String downloadsLoading = '正在读取已下载的歌曲…';
  static const String downloadsEmptyTitle = '还没有下载到这台设备的歌曲';
  static const String downloadsEmptyMessage = '在“歌曲”里点下载，歌曲会保存到这台设备，离线也能播放。';
}

/// A dismissible error line above a transfer list.
class TransferErrorBanner extends StatelessWidget {
  const TransferErrorBanner({super.key, required this.message, this.onDismiss});

  final String message;

  /// Shows a close button when set.
  final VoidCallback? onDismiss;

  static const String dismissTooltip = '关闭提示';

  @override
  Widget build(BuildContext context) {
    final dismiss = onDismiss;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          dismiss == null ? AppSpacing.md : AppSpacing.xs,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(20),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          border: Border.all(color: AppColors.error.withAlpha(70)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: AppColors.errorText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.errorText),
              ),
            ),
            if (dismiss != null)
              IconButton(
                tooltip: dismissTooltip,
                onPressed: dismiss,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// Spinner with a sentence while a transfer list loads for the first time.
class TransferListLoading extends StatelessWidget {
  const TransferListLoading({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(child: AppInlineLoading(message: message)),
    );
  }
}

/// Why a transfer list shows no rows.
enum TransferEmptyReason {
  /// The search text matched nothing.
  search,

  /// A filter chip hid every row.
  filter,

  /// There is nothing at all.
  nothing,
}

/// What a transfer list shows when it has no rows: a reason-specific title
/// and the button that brings the rows back.
class TransferEmptyResult extends StatelessWidget {
  const TransferEmptyResult({
    super.key,
    required this.icon,
    required this.noun,
    required this.emptyTitle,
    this.emptyMessage,
    this.query = '',
    this.onClearSearch,
    this.filteredTitle,
    this.onShowAll,
  });

  final IconData icon;

  /// What the list holds, for example "歌曲" or "专辑".
  final String noun;

  /// Title when there is nothing at all, for example "桌面音乐库里还没有歌曲".
  final String emptyTitle;

  /// Next step when there is nothing at all.
  final String? emptyMessage;

  /// The search text; blank when the user is not searching.
  final String query;

  /// Clears the search; shows the "清除搜索" button when set.
  final VoidCallback? onClearSearch;

  /// Title while a filter is active, for example "还没有已下载的歌曲"; null
  /// when no filter is active.
  final String? filteredTitle;

  /// Drops the filter; shows the "显示全部" button when set.
  final VoidCallback? onShowAll;

  static const String clearSearchLabel = '清除搜索';
  static const String showAllLabel = '显示全部';

  /// The search wins over the filter: it is what the user typed last, and
  /// clearing it may already bring rows back.
  static TransferEmptyReason reasonFor({
    required String query,
    required bool filtered,
  }) {
    if (query.trim().isNotEmpty) return TransferEmptyReason.search;
    if (filtered) return TransferEmptyReason.filter;
    return TransferEmptyReason.nothing;
  }

  /// Title for a search that matched nothing.
  static String searchTitle(String query, String noun) =>
      '没有匹配“${query.trim()}”的$noun';

  static const String searchMessage = '换个关键词，或清除搜索查看全部。';
  static const String filterMessage = '当前筛选下没有内容，可以显示全部。';

  TransferEmptyReason get reason =>
      reasonFor(query: query, filtered: filteredTitle != null);

  @override
  Widget build(BuildContext context) {
    final (title, message, action) = switch (reason) {
      TransferEmptyReason.search => (
        searchTitle(query, noun),
        searchMessage,
        onClearSearch == null
            ? null
            : OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.search_off_rounded),
                label: const Text(clearSearchLabel),
              ),
      ),
      TransferEmptyReason.filter => (
        filteredTitle!,
        filterMessage,
        onShowAll == null
            ? null
            : OutlinedButton.icon(
                onPressed: onShowAll,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text(showAllLabel),
              ),
      ),
      TransferEmptyReason.nothing => (emptyTitle, emptyMessage, null),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: AppEmptyState(
        icon: reason == TransferEmptyReason.search
            ? Icons.search_off_rounded
            : icon,
        title: title,
        message: message,
        density: AppEmptyStateDensity.panel,
        actions: [?action],
      ),
    );
  }
}
