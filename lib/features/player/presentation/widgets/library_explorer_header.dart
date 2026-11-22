import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/local_library_browse_item.dart';

/// The top of the 歌曲 section of the music library (D-059).
///
/// It used to be five loose rows — search, a sort drop-down, a 40 dp
/// grid/list switch and a 48 dp 播放结果 button side by side at three
/// different heights, the filter chips, and two lines of counts — with the
/// same weight on all of them. Now it reads in order of use:
///
///  1. the search field;
///  2. one toolbar row, every control the same touch height: 播放全部
///     (the one filled, violet button), 随机播放 next to it, then the quiet
///     tools — sort, grid or list and, on a phone, the library menu;
///  3. the filter chips, smaller than the section strip's above them;
///  4. one quiet line of counts.
class LibraryExplorerHeader extends StatelessWidget {
  const LibraryExplorerHeader({
    super.key,
    required this.controller,
    required this.query,
    required this.total,
    required this.visible,
    required this.playable,
    required this.smartView,
    required this.sortMode,
    required this.grid,
    required this.countFor,
    required this.onQuery,
    required this.onClearQuery,
    required this.onSmartView,
    required this.onSortMode,
    required this.onGrid,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onCleanMissing,
    this.menu,
  });

  final TextEditingController controller;
  final String query;
  final int total;
  final int visible;
  final int playable;
  final LocalLibrarySmartView smartView;
  final LocalLibrarySortMode sortMode;
  final bool grid;
  final int Function(LocalLibrarySmartView view) countFor;
  final ValueChanged<String> onQuery;
  final VoidCallback onClearQuery;
  final ValueChanged<LocalLibrarySmartView> onSmartView;
  final ValueChanged<LocalLibrarySortMode> onSortMode;
  final ValueChanged<bool> onGrid;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;
  final VoidCallback? onCleanMissing;

  /// The library menu (refresh, import), at the end of the toolbar; the
  /// phone has no app bar for it.
  final Widget? menu;

  static const Key playAllKey = ValueKey('library-explorer:play-all');
  static const Key shuffleKey = ValueKey('library-explorer:shuffle');
  static const Key sortKey = ValueKey('library-explorer:sort');
  static const Key viewKey = ValueKey('library-explorer:view');
  static const Key countsKey = ValueKey('library-explorer:counts');

  static const String playAllLabel = '播放全部';
  static const String playResultsLabel = '播放结果';
  static const String shuffleTooltip = '随机播放';

  /// 播放全部 while the whole library shows, 播放结果 after a search or
  /// filter narrowed it.
  static String playLabel({required int visible, required int total}) =>
      visible == total ? playAllLabel : playResultsLabel;

  /// The line of counts: `128 首歌曲`, `12 / 128 首`, then what cannot be
  /// played, only when something cannot.
  static String countsLabel({
    required int total,
    required int visible,
    required int playable,
  }) {
    final shown = visible == total ? '$total 首歌曲' : '$visible / $total 首';
    final unplayable = visible - playable;
    return unplayable > 0 ? '$shown · $unplayable 首不可播放' : shown;
  }

  static String sortLabel(LocalLibrarySortMode mode) => switch (mode) {
    LocalLibrarySortMode.title => '标题 A-Z',
    LocalLibrarySortMode.artist => '按艺人',
    LocalLibrarySortMode.album => '按专辑',
    LocalLibrarySortMode.recentlyAdded => '最近添加',
    LocalLibrarySortMode.recentlyPlayed => '最近播放',
  };

  static String smartLabel(LocalLibrarySmartView view) => switch (view) {
    LocalLibrarySmartView.all => '全部',
    LocalLibrarySmartView.recentlyAdded => '最近添加',
    LocalLibrarySmartView.recentlyPlayed => '最近播放',
    LocalLibrarySmartView.withLyrics => '有歌词',
    LocalLibrarySmartView.withoutLyrics => '无歌词',
    LocalLibrarySmartView.autoPairedLyrics => '自动配对',
    LocalLibrarySmartView.editedMetadata => '已编辑资料',
    LocalLibrarySmartView.missingFiles => '文件不可用',
  };

  /// 自动配对 appears once some song got its lyrics that way.
  bool _showsChip(LocalLibrarySmartView view) =>
      view != LocalLibrarySmartView.autoPairedLyrics ||
      view == smartView ||
      countFor(view) > 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final extent = layout.minimumInteractiveExtent;
        final textTheme = Theme.of(context).textTheme;

        final search = TextField(
          controller: controller,
          onChanged: onQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: layout.isCompact ? '搜索歌曲、艺人、专辑' : '搜索歌曲、艺人、专辑、流派、文件名或歌单',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            constraints: BoxConstraints.tightFor(height: extent),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: onClearQuery,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        );

        final square = Size.square(extent);
        final tools = <Widget>[
          PopupMenuButton<LocalLibrarySortMode>(
            key: sortKey,
            tooltip: '排序：${sortLabel(sortMode)}',
            initialValue: sortMode,
            onSelected: onSortMode,
            itemBuilder: (_) => [
              for (final mode in LocalLibrarySortMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == sortMode,
                  child: Text(sortLabel(mode)),
                ),
            ],
            child: SizedBox.fromSize(
              size: square,
              child: Icon(Icons.sort_rounded, color: AppColors.textSecondary),
            ),
          ),
          IconButton(
            key: viewKey,
            tooltip: grid ? '列表显示' : '网格显示',
            style: IconButton.styleFrom(minimumSize: square),
            color: AppColors.textSecondary,
            onPressed: () => onGrid(!grid),
            icon: Icon(
              grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
          ?menu,
        ];

        // The tools keep their size; 播放全部 gives way on a narrow phone,
        // its label shortening rather than pushing the row over the edge.
        final toolbar = Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: FilledButton.icon(
                      key: playAllKey,
                      style: AppTheme.vinylFilled.copyWith(
                        minimumSize: WidgetStatePropertyAll(
                          Size(extent, extent),
                        ),
                        shape: const WidgetStatePropertyAll(StadiumBorder()),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        ),
                      ),
                      onPressed: onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        playLabel(visible: visible, total: total),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filledTonal(
                    key: shuffleKey,
                    tooltip: shuffleTooltip,
                    style: IconButton.styleFrom(minimumSize: square),
                    onPressed: onShuffle,
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                ],
              ),
            ),
            ...tools,
          ],
        );

        final chips = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final view in LocalLibrarySmartView.values.where(_showsChip))
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  // Smaller and without icons: the filters come under the
                  // section strip's chips, not beside them.
                  child: FilterChip(
                    selected: view == smartView,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onSmartView(view),
                    label: Text('${smartLabel(view)} ${countFor(view)}'),
                  ),
                ),
            ],
          ),
        );

        final counts = Row(
          key: countsKey,
          children: [
            Expanded(
              child: Text(
                [
                  countsLabel(
                    total: total,
                    visible: visible,
                    playable: playable,
                  ),
                  if (smartView == LocalLibrarySmartView.recentlyAdded)
                    '过去 30 天',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            if (onCleanMissing != null)
              TextButton(
                onPressed: onCleanMissing,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('清理缺失项'),
              ),
          ],
        );

        final wide = layout.isLarge || layout.isExtraLarge;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pageGutter,
            AppSpacing.md,
            layout.pageGutter,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: toolbar),
                  ],
                )
              else ...[
                search,
                const SizedBox(height: AppSpacing.md),
                toolbar,
              ],
              const SizedBox(height: AppSpacing.md),
              chips,
              const SizedBox(height: AppSpacing.sm),
              counts,
            ],
          ),
        );
      },
    );
  }
}
