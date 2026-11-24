import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_catalog_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/models/local_playlist.dart';
import 'local_library_semantics.dart';

class FavoriteCollectionSongActions extends StatelessWidget {
  final bool compact;
  final bool canPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onRemoveFavorite;
  final VoidCallback onAddToPlaylist;

  const FavoriteCollectionSongActions({
    super.key,
    required this.compact,
    required this.canPlay,
    required this.onEnqueue,
    required this.onRemoveFavorite,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return PopupMenuButton<String>(
        tooltip: '歌曲操作',
        onSelected: (value) {
          if (value == 'queue' && canPlay) onEnqueue();
          if (value == 'unfavorite') onRemoveFavorite();
          if (value == 'playlist') onAddToPlaylist();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'queue',
            enabled: canPlay,
            child: const Text('加入播放队列'),
          ),
          const PopupMenuItem(value: 'playlist', child: Text('加入播放列表')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'unfavorite', child: Text('取消收藏')),
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        IconButton(
          tooltip: '加入播放队列',
          onPressed: canPlay ? onEnqueue : null,
          icon: const Icon(Icons.queue_music_rounded),
        ),
        IconButton(
          tooltip: '取消收藏',
          onPressed: onRemoveFavorite,
          icon: const Icon(Icons.favorite_rounded),
        ),
        IconButton(
          tooltip: '加入播放列表',
          onPressed: onAddToPlaylist,
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ],
    );
  }
}

class PlaylistCollectionSongActions extends StatelessWidget {
  final int index;
  final bool compact;
  final bool canPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onRemove;

  const PlaylistCollectionSongActions({
    super.key,
    required this.index,
    required this.compact,
    required this.canPlay,
    required this.onEnqueue,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final dragHandle = Tooltip(
      message: '拖动排序',
      child: ReorderableDragStartListener(
        index: index,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.drag_handle_rounded),
        ),
      ),
    );

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: '歌曲操作',
            onSelected: (value) {
              if (value == 'queue' && canPlay) onEnqueue();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'queue',
                enabled: canPlay,
                child: const Text('加入播放队列'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'remove', child: Text('从播放列表移除')),
            ],
          ),
          dragHandle,
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: '加入播放队列',
          onPressed: canPlay ? onEnqueue : null,
          icon: const Icon(Icons.queue_music_rounded),
        ),
        IconButton(
          tooltip: '从播放列表移除',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        dragHandle,
      ],
    );
  }
}

class CollectionHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  const CollectionHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final compact = spec.isCompactOrMedium || spec.isShort;
    final extent = spec.isCompact ? 56.0 : 72.0;
    final button = FilledButton.icon(
      onPressed: onPrimary,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(primaryLabel),
      style: FilledButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );

    return Padding(
      padding: EdgeInsets.all(spec.pageGutter),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spec.isCompact ? AppSpacing.md : AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _HeroIcon(icon: icon, extent: extent),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _HeroText(
                          title: title,
                          subtitle: subtitle,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(width: double.infinity, child: button),
                ],
              )
            : Row(
                children: [
                  _HeroIcon(icon: icon, extent: extent),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _HeroText(title: title, subtitle: subtitle),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  button,
                ],
              ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  final IconData icon;
  final double extent;

  const _HeroIcon({required this.icon, required this.extent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        color: AppColors.bgHighlight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Icon(icon, size: extent * 0.52),
    );
  }
}

class _HeroText extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;

  const _HeroText({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class PlaylistDetailHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool canPlay;
  final bool canAddCurrent;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onAddCurrent;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const PlaylistDetailHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.canPlay,
    required this.canAddCurrent,
    required this.onBack,
    required this.onPlay,
    required this.onAddCurrent,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final compact = spec.isCompactOrMedium || spec.isShort;

    final menu = PopupMenuButton<String>(
      tooltip: '播放列表操作',
      onSelected: (value) {
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('删除播放列表')),
      ],
    );

    final playButton = FilledButton.icon(
      onPressed: canPlay ? onPlay : null,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('播放'),
      style: FilledButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );
    final addButton = OutlinedButton.icon(
      onPressed: canAddCurrent ? onAddCurrent : null,
      icon: const Icon(Icons.add_rounded),
      label: const Text('加入当前歌曲'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: spec.minimumInteractiveExtent,
                      height: spec.minimumInteractiveExtent,
                      child: IconButton(
                        tooltip: '返回播放列表',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _PlaylistTitleBlock(
                        name: name,
                        subtitle: subtitle,
                        compact: true,
                      ),
                    ),
                    menu,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: playButton),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: addButton),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  tooltip: '返回播放列表',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PlaylistTitleBlock(name: name, subtitle: subtitle),
                ),
                playButton,
                const SizedBox(width: AppSpacing.sm),
                addButton,
                menu,
              ],
            ),
    );
  }
}

class _PlaylistTitleBlock extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool compact;

  const _PlaylistTitleBlock({
    required this.name,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class LocalPlaylistCard extends StatelessWidget {
  final LocalPlaylist playlist;
  final String? artworkPath;
  final int missing;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const LocalPlaylistCard({
    super.key,
    required this.playlist,
    required this.artworkPath,
    required this.missing,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  /// 12 首歌曲 · 2 首不可用.
  String get summary => [
    '${playlist.sourcePaths.length} 首歌曲',
    if (missing > 0) '$missing 首不可用',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);

    return AppCatalogCard(
      semanticLabel: LocalLibrarySemantics.playlistCard(
        name: playlist.name,
        songs: playlist.sourcePaths.length,
        missing: missing,
      ),
      semanticHint: LocalLibrarySemantics.openPlaylistHint,
      onTap: onOpen,
      semanticActions: {'重命名': onRename, '删除播放列表': onDelete},
      compact: spec.isCompact,
      artwork: AppArtwork(
        path: artworkPath,
        borderRadius: AppArtwork.tileRadius,
        placeholderIcon: Icons.queue_music_rounded,
      ),
      artworkOverlay: Material(
        color: AppColors.pureBlack.withAlpha(90),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        child: PopupMenuButton<String>(
          tooltip: '播放列表操作',
          // White on the dimmed cover in either theme.
          iconColor: AppColors.pureWhite,
          onSelected: (value) {
            if (value == 'rename') onRename();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('删除播放列表')),
          ],
        ),
      ),
      title: playlist.name,
      subtitle: summary,
      subtitleIsAlert: missing > 0,
    );
  }
}

class CollectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CollectionEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;
    return AppEmptyState(
      icon: icon,
      title: title,
      message: message,
      actions: [
        if (label != null && action != null)
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.add_rounded),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: Size(
                0,
                AppResponsive.of(context).minimumInteractiveExtent,
              ),
            ),
          ),
      ],
    );
  }
}
