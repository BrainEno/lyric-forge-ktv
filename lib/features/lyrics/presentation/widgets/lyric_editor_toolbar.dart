import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/presentation/widgets/seekable_progress_bar.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../lyric_review_strings.dart';
import 'lyric_proofread_menu_button.dart';

/// Which lines the editor list shows.
///
/// Public because [LyricEditorToolbar] renders it; the filter itself is pure
/// view state and never leaves the presentation layer.
enum LyricReviewFilter { all, needsReview, lowConfidence, smartReview }

/// The editor's control strip.
///
/// It used to offer roughly twenty controls in one band — four read-only
/// metrics, four filter chips, a play button, an insert button, six
/// proofreading buttons, two toggles, a player link, four offset controls and a
/// progress bar — and on narrow widths the whole row turned into a horizontal
/// scroll with no scrollbar, so everything on the right simply did not exist.
///
/// The controls that are used while reviewing a line stay visible (play,
/// filter, follow, offset, and the single proofreading menu on wide layouts).
/// Everything else moved to [LyricEditorOverflowMenu] in the app bar or is
/// derived information shown as text. The strip now uses a [Wrap] at every
/// width, so nothing is ever off-screen.
class LyricEditorToolbar extends StatelessWidget {
  final LyricDocument document;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int lowConfidenceCount;
  final int reviewCount;
  final int smartReviewCount;
  final LyricReviewFilter filter;
  final ValueChanged<LyricReviewFilter> onFilterChanged;
  final bool loopCurrentLineAudition;
  final ValueChanged<bool> onLoopCurrentLineAuditionChanged;
  final bool followPlayback;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<Duration> onUpdateOffset;
  final VoidCallback onTogglePlayback;
  final ValueChanged<Duration> onSeekPlayback;
  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onReferenceProofread;
  final VoidCallback? onProofreadV2;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;

  const LyricEditorToolbar({
    super.key,
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.lowConfidenceCount,
    required this.reviewCount,
    required this.smartReviewCount,
    required this.filter,
    required this.onFilterChanged,
    required this.loopCurrentLineAudition,
    required this.onLoopCurrentLineAuditionChanged,
    required this.followPlayback,
    required this.onFollowPlaybackChanged,
    required this.onUpdateOffset,
    required this.onTogglePlayback,
    required this.onSeekPlayback,
    required this.onReferenceAlignment,
    required this.onReferenceProofread,
    required this.onProofreadV2,
    required this.onUndoReferenceAlignment,
    required this.onViewAlignmentComparison,
    required this.onRestoreAlignment,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final offset = document.globalOffset ?? Duration.zero;
    // Narrow layouts carry the proofreading menu in the app bar, so the strip
    // does not repeat it.
    final showProofreadMenu = !(spec.isCompactOrMedium || spec.isShort);
    final horizontalPadding = spec.pageGutter.clamp(12, 24).toDouble();

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppSpacing.sm,
        horizontalPadding,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(
            lineCount: document.lines.length,
            language: document.language,
            reviewCount: reviewCount,
            lowConfidenceCount: lowConfidenceCount,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: spec.minimumInteractiveExtent,
                height: spec.minimumInteractiveExtent,
                child: IconButton(
                  tooltip: playbackBelongsToProject && playback.isPlaying
                      ? '暂停试听'
                      : '继续试听',
                  onPressed: onTogglePlayback,
                  icon: Icon(
                    playbackBelongsToProject && playback.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                ),
              ),
              if (!playbackBelongsToProject)
                Text(
                  '尚未开始试听',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              _FilterMenu(
                filter: filter,
                reviewCount: reviewCount,
                lowConfidenceCount: lowConfidenceCount,
                smartReviewCount: smartReviewCount,
                onChanged: onFilterChanged,
              ),
              FilterChip(
                selected: followPlayback,
                onSelected: onFollowPlaybackChanged,
                avatar: Icon(
                  followPlayback
                      ? Icons.my_location_rounded
                      : Icons.location_disabled_rounded,
                  size: 16,
                ),
                label: const Text('跟随播放'),
              ),
              _OffsetMenu(offset: offset, onChanged: onUpdateOffset),
              if (filter == LyricReviewFilter.smartReview)
                Tooltip(
                  message: LyricReviewStrings.loopCurrentLineHelp,
                  child: FilterChip(
                    selected: loopCurrentLineAudition,
                    onSelected: onLoopCurrentLineAuditionChanged,
                    avatar: const Icon(Icons.repeat_rounded, size: 16),
                    label: const Text(LyricReviewStrings.loopCurrentLineLabel),
                  ),
                ),
              if (showProofreadMenu)
                LyricProofreadMenuButton(
                  onProofreadV2: onProofreadV2,
                  onReferenceAlignment: onReferenceAlignment,
                  onReferenceProofread: onReferenceProofread,
                  onViewComparison: onViewAlignmentComparison,
                  onUndoAlignment: onUndoReferenceAlignment,
                  onRestoreBackup: onRestoreAlignment,
                ),
            ],
          ),
          if (playbackBelongsToProject) ...[
            const SizedBox(height: AppSpacing.xs),
            SeekableProgressBar(
              state: playback,
              onSeek: onSeekPlayback,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// The editor actions that are not used on every line.
///
/// These used to be first-class buttons in the control strip or in the app bar
/// (insert at playback position appeared in two places at once). One menu keeps
/// them reachable without asking the user to scan for them on every screenshot.
class LyricEditorOverflowMenu extends StatelessWidget {
  final bool canExport;
  final VoidCallback onExport;
  final VoidCallback? onInsertAtPlayback;
  final VoidCallback? onOpenPlayer;

  const LyricEditorOverflowMenu({
    super.key,
    required this.canExport,
    required this.onExport,
    required this.onInsertAtPlayback,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final openPlayer = onOpenPlayer;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: onInsertAtPlayback,
          leadingIcon: const Icon(Icons.playlist_add_rounded, size: 18),
          child: _OverflowLabel(
            title: '在播放位置插入',
            detail: onInsertAtPlayback == null ? '先试听本工程' : '在当前试听时间插入一行',
          ),
        ),
        if (canExport)
          MenuItemButton(
            onPressed: onExport,
            leadingIcon: const Icon(Icons.download_rounded, size: 18),
            child: const _OverflowLabel(title: '导出 LRC', detail: '保存为 .lrc 文件'),
          ),
        if (openPlayer != null)
          MenuItemButton(
            onPressed: openPlayer,
            leadingIcon: const Icon(Icons.open_in_full_rounded, size: 18),
            child: const _OverflowLabel(title: '完整播放器', detail: '全屏播放并对照歌词'),
          ),
      ],
      builder: (context, controller, child) {
        void open() {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        }

        return IconButton(
          tooltip: '更多',
          onPressed: open,
          icon: const Icon(Icons.more_vert_rounded),
        );
      },
    );
  }
}

/// Read-only line statistics, as one line of text instead of four pills.
class _StatusLine extends StatelessWidget {
  final int lineCount;
  final String language;
  final int reviewCount;
  final int lowConfidenceCount;

  const _StatusLine({
    required this.lineCount,
    required this.language,
    required this.reviewCount,
    required this.lowConfidenceCount,
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    Widget item(String text, Color color) =>
        Text(text, style: base?.copyWith(color: color));
    const separator = Text('·');

    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item('$lineCount 行', AppColors.textTertiary),
        separator,
        item(language.toUpperCase(), AppColors.textTertiary),
        separator,
        item(
          '待复核 $reviewCount',
          reviewCount > 0 ? AppColors.accent : AppColors.textTertiary,
        ),
        separator,
        item(
          '低置信度 $lowConfidenceCount',
          lowConfidenceCount > 0 ? AppColors.warning : AppColors.textTertiary,
        ),
      ],
    );
  }
}

/// The four review filters, collapsed from a row of chips into one menu.
class _FilterMenu extends StatelessWidget {
  final LyricReviewFilter filter;
  final int reviewCount;
  final int lowConfidenceCount;
  final int smartReviewCount;
  final ValueChanged<LyricReviewFilter> onChanged;

  const _FilterMenu({
    required this.filter,
    required this.reviewCount,
    required this.lowConfidenceCount,
    required this.smartReviewCount,
    required this.onChanged,
  });

  String _label(LyricReviewFilter value) {
    return switch (value) {
      LyricReviewFilter.all => '全部',
      LyricReviewFilter.needsReview => '待复核 $reviewCount',
      LyricReviewFilter.lowConfidence => '低置信度 $lowConfidenceCount',
      LyricReviewFilter.smartReview => '智能复核 $smartReviewCount',
    };
  }

  String? _detail(LyricReviewFilter value) {
    return switch (value) {
      LyricReviewFilter.all => null,
      LyricReviewFilter.needsReview => '引擎不确定或低于阈值的行',
      LyricReviewFilter.lowConfidence => '按引擎给出的分值筛选',
      LyricReviewFilter.smartReview => '按低置信度、双引擎分歧与时间轴异常排序',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final value in LyricReviewFilter.values)
          MenuItemButton(
            onPressed: () => onChanged(value),
            leadingIcon: Icon(
              value == filter
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 18,
            ),
            child: _OverflowLabel(title: _label(value), detail: _detail(value)),
          ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: '筛选要显示的行',
          child: OutlinedButton.icon(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.filter_list_rounded, size: 18),
            label: Text(_label(filter)),
          ),
        );
      },
    );
  }
}

/// Global offset nudge, collapsed into one button that shows the current value.
class _OffsetMenu extends StatelessWidget {
  final Duration offset;
  final ValueChanged<Duration> onChanged;

  const _OffsetMenu({required this.offset, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () =>
              onChanged(offset - const Duration(milliseconds: 100)),
          leadingIcon: const Icon(Icons.remove_rounded, size: 18),
          child: const _OverflowLabel(title: '提前 100ms', detail: '歌词整体早一点出现'),
        ),
        MenuItemButton(
          onPressed: () =>
              onChanged(offset + const Duration(milliseconds: 100)),
          leadingIcon: const Icon(Icons.add_rounded, size: 18),
          child: const _OverflowLabel(title: '延后 100ms', detail: '歌词整体晚一点出现'),
        ),
        MenuItemButton(
          onPressed: offset == Duration.zero
              ? null
              : () => onChanged(Duration.zero),
          leadingIcon: const Icon(Icons.restart_alt_rounded, size: 18),
          child: _OverflowLabel(
            title: '归零',
            detail: offset == Duration.zero ? '当前无偏移' : '恢复为不偏移',
          ),
        ),
      ],
      builder: (context, controller, child) {
        return Tooltip(
          message: '全局偏移：整首歌词统一平移，不影响单行时间',
          child: OutlinedButton.icon(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(
              '偏移 ${_formatSignedDuration(offset)}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverflowLabel extends StatelessWidget {
  const _OverflowLabel({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = this.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              detail,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

String _formatSignedDuration(Duration duration) {
  if (duration == Duration.zero) return '0ms';
  final sign = duration.isNegative ? '-' : '+';
  final milliseconds = duration.inMilliseconds.abs();
  if (milliseconds >= 1000) {
    return '$sign${(milliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '$sign${milliseconds}ms';
}
