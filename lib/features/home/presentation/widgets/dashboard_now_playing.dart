// The dashboard's top area: the idle hero, the playing hero with its
// transport, and the playback queue card next to it.
//
// Split out of `dashboard_screen.dart` (audit D-06).

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/playback_session_service.dart';
import 'dashboard_semantics.dart';
import 'dashboard_surfaces.dart';

class DashboardNowPlayingArea extends StatelessWidget {
  final PlaybackSessionState session;
  final PlaybackState playback;
  final VoidCallback onOpenMusic;
  final ValueChanged<PlaybackItem> onOpenCurrent;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;
  final Future<void> Function(PlaybackItem) onPlayQueueItem;

  const DashboardNowPlayingArea({
    super.key,
    required this.session,
    required this.playback,
    required this.onOpenMusic,
    required this.onOpenCurrent,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayQueueItem,
  });

  @override
  Widget build(BuildContext context) {
    final current = session.currentItem;
    final hero = current == null
        ? _IdleHero(onOpenMusic: onOpenMusic)
        : _PlayingHero(
            item: current,
            playback: playback,
            session: session,
            onOpen: () => onOpenCurrent(current),
            onPlayPause: onPlayPause,
            onPrevious: onPrevious,
            onNext: onNext,
          );
    final queue = _PlaybackQueueCard(
      session: session,
      onPlayItem: onPlayQueueItem,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        if (!layout.supportsTwoPane) {
          return Column(
            children: [
              hero,
              SizedBox(height: layout.sectionGap),
              queue,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: hero),
            SizedBox(width: layout.sectionGap),
            SizedBox(width: layout.sidePanelWidth, child: queue),
          ],
        );
      },
    );
  }
}

class _IdleHero extends StatelessWidget {
  final VoidCallback onOpenMusic;

  const _IdleHero({required this.onOpenMusic});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final showArtwork =
            !layout.isShort &&
            (layout.isExpanded || layout.isLarge || layout.isExtraLarge);
        final minHeight = layout.isShort
            ? 190.0
            : layout.isCompact
            ? 220.0
            : 250.0;
        return Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.all(
            layout.isCompact ? AppSpacing.md : AppSpacing.xl,
          ),
          decoration: dashboardHeroDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DashboardEyebrow('LOCAL FIRST'),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '把你的音乐库变成\n可以继续制作的 KTV 工程',
                      style:
                          (layout.isCompact
                                  ? Theme.of(context).textTheme.headlineSmall
                                  : Theme.of(context).textTheme.headlineMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '先正常听歌，需要歌词时再交给后台批量识别。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: Size(
                          layout.minimumInteractiveExtent,
                          layout.minimumInteractiveExtent,
                        ),
                      ),
                      onPressed: onOpenMusic,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('选择音乐开始播放'),
                    ),
                  ],
                ),
              ),
              if (showArtwork) ...[
                SizedBox(width: layout.sectionGap),
                DashboardArtwork(size: layout.isExpanded ? 130 : 150),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PlayingHero extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final VoidCallback onOpen;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;

  const _PlayingHero({
    required this.item,
    required this.playback,
    required this.session,
    required this.onOpen,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final compact = layout.isCompactOrMedium || layout.isShort;
        final artworkSize = layout.isShort
            ? 88.0
            : layout.isCompact
            ? 104.0
            : layout.isMedium
            ? 120.0
            : 172.0;
        final detail = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardEyebrow('正在播放'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              item.artist?.trim().isNotEmpty == true
                  ? item.artist!
                  : item.projectId == null
                  ? '本地音乐'
                  : 'Elysium Player 工程',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _HeroProgress(playback),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: layout.minimumInteractiveExtent,
                  height: layout.minimumInteractiveExtent,
                  child: IconButton.filledTonal(
                    tooltip: '上一首 / 回到开头',
                    onPressed: onPrevious,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                ),
                SizedBox(
                  width: layout.primaryPlayerControlExtent,
                  height: layout.primaryPlayerControlExtent,
                  child: IconButton.filled(
                    tooltip: playback.isPlaying ? '暂停' : '播放',
                    onPressed: playback.isBuffering ? null : onPlayPause,
                    style: AppTheme.busyAccentDisc,
                    icon: playback.isBuffering
                        ? const AppButtonSpinner()
                        : Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  ),
                ),
                SizedBox(
                  width: layout.minimumInteractiveExtent,
                  height: layout.minimumInteractiveExtent,
                  child: IconButton.filledTonal(
                    tooltip: '下一首',
                    onPressed: session.canSkipNext ? onNext : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(
                      layout.minimumInteractiveExtent,
                      layout.minimumInteractiveExtent,
                    ),
                  ),
                  onPressed: onOpen,
                  icon: Icon(
                    item.projectId == null
                        ? Icons.open_in_new_rounded
                        : Icons.lyrics_rounded,
                    size: 17,
                  ),
                  label: Text(item.projectId == null ? '打开播放器' : '打开歌词播放器'),
                ),
              ],
            ),
          ],
        );

        return Container(
          constraints: BoxConstraints(
            minHeight: layout.isShort
                ? 190
                : layout.isCompact
                ? 220
                : 250,
          ),
          padding: EdgeInsets.all(
            layout.isCompact ? AppSpacing.md : AppSpacing.lg,
          ),
          decoration: dashboardHeroDecoration(),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DashboardArtwork(path: item.artworkPath, size: artworkSize),
                    const SizedBox(height: AppSpacing.md),
                    detail,
                  ],
                )
              : Row(
                  children: [
                    DashboardArtwork(path: item.artworkPath, size: artworkSize),
                    SizedBox(width: layout.sectionGap),
                    Expanded(child: detail),
                  ],
                ),
        );
      },
    );
  }
}

class _HeroProgress extends StatelessWidget {
  final PlaybackState playback;
  const _HeroProgress(this.playback);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: playback.progressPercent.clamp(0.0, 1.0).toDouble(),
          minHeight: 4,
          backgroundColor: AppColors.bgHighlight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text(
              playback.formattedPosition,
              style: dashboardMutedLabel(context),
            ),
            const Spacer(),
            Text(
              playback.formattedDuration,
              style: dashboardMutedLabel(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackQueueCard extends StatelessWidget {
  final PlaybackSessionState session;
  final Future<void> Function(PlaybackItem) onPlayItem;

  const _PlaybackQueueCard({required this.session, required this.onPlayItem});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final start = session.currentIndex < 0 ? 0 : session.currentIndex;
    final visibleCount = layout.isShort
        ? 3
        : layout.isCompact
        ? 4
        : 5;
    final end = (start + visibleCount).clamp(0, session.queue.length).toInt();
    final items = start < end
        ? session.queue.sublist(start, end)
        : const <PlaybackItem>[];

    return Container(
      constraints: BoxConstraints(
        minHeight: layout.isShort
            ? 180
            : layout.isCompact
            ? 220
            : 250,
      ),
      padding: EdgeInsets.all(layout.isCompact ? AppSpacing.sm : AppSpacing.md),
      decoration: dashboardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '播放队列',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${session.queue.length} 首',
                style: dashboardMutedLabel(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            SizedBox(
              height: layout.isShort ? 100 : 155,
              child: Center(
                child: Text(
                  '播放音乐后，这里会显示当前队列',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < items.length; i++)
              _QueueRow(
                item: items[i],
                current: start + i == session.currentIndex,
                onTap: () => onPlayItem(items[i]),
              ),
          if (session.queue.length > end && items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '还有 ${session.queue.length - end} 首未显示',
              style: dashboardMutedLabel(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final PlaybackItem item;
  final bool current;
  final VoidCallback onTap;

  const _QueueRow({
    required this.item,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final source = item.artist?.trim().isNotEmpty == true
        ? item.artist!
        : item.projectId == null
        ? '本地音乐'
        : '歌词工程';
    return Material(
      color: current ? AppColors.accent.withAlpha(16) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: AppTapTarget(
        label: DashboardSemantics.queueRow(
          title: item.title,
          source: source,
          current: current,
        ),
        hint: current ? null : DashboardSemantics.playNowHint,
        selected: current,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                DashboardArtwork(
                  path: item.artworkPath,
                  size: layout.minimumInteractiveExtent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: current
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          fontWeight: current
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dashboardMutedLabel(context),
                      ),
                    ],
                  ),
                ),
                Icon(
                  current ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                  size: 18,
                  color: current ? AppColors.accent : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
