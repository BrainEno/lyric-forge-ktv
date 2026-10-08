import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/playback_session_service.dart';
import 'playback_action_feedback.dart';
import 'playback_mode_controls.dart';

class PlaybackQueuePanel extends StatelessWidget {
  final PlaybackSessionService session;
  final double height;
  final bool allowClearAll;
  final bool showBorder;

  const PlaybackQueuePanel({
    super.key,
    required this.session,
    this.height = 360,
    this.allowClearAll = false,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackSessionState>(
      stream: session.stateStream,
      initialData: session.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackSessionState();
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            border: showBorder ? Border.all(color: AppColors.borderMuted) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _QueueHeader(
                session: session,
                state: state,
                allowClearAll: allowClearAll,
                onClearUpcoming: state.upcomingCount > 0
                    ? () => session.clearQueue()
                    : null,
                onClearAll: state.queue.isNotEmpty && allowClearAll
                    ? () => session.clearQueue(keepCurrent: false)
                    : null,
              ),
              const Divider(height: 1, color: AppColors.borderMuted),
              Expanded(
                child: state.queue.isEmpty
                    ? const _EmptyQueue()
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: state.queue.length,
                        onReorder: (oldIndex, newIndex) {
                          var target = newIndex;
                          if (target > oldIndex) target -= 1;
                          if (target < 0 || target >= state.queue.length) return;
                          session.moveItem(oldIndex, target);
                        },
                        itemBuilder: (context, index) {
                          final item = state.queue[index];
                          return _QueueRow(
                            key: ValueKey(item.id),
                            index: index,
                            item: item,
                            isCurrent: index == state.currentIndex,
                            onPlay: () => runPlaybackActionWithFeedback(
                              context,
                              () => session.playAt(index),
                            ),
                            onRemove: () => session.removeAt(index),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueHeader extends StatelessWidget {
  final PlaybackSessionService session;
  final PlaybackSessionState state;
  final bool allowClearAll;
  final VoidCallback? onClearUpcoming;
  final VoidCallback? onClearAll;

  const _QueueHeader({
    required this.session,
    required this.state,
    required this.allowClearAll,
    required this.onClearUpcoming,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '播放队列',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              PlaybackModeControls(session: session, compact: true),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.currentItem == null
                      ? '暂无歌曲'
                      : '${state.queue.length} 首 · 待播 ${state.upcomingCount} 首',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
              TextButton(
                onPressed: onClearUpcoming,
                child: const Text('清空待播'),
              ),
              if (allowClearAll)
                IconButton(
                  tooltip: '停止并清空全部',
                  onPressed: onClearAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int index;
  final PlaybackItem item;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  const _QueueRow({
    super.key,
    required this.index,
    required this.item,
    required this.isCurrent,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? AppColors.accent.withAlpha(16) : Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xs),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _QueueArtwork(item: item),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          const Icon(
                            Icons.graphic_eq_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: isCurrent
                                      ? AppColors.accent
                                      : AppColors.textPrimary,
                                  fontWeight: isCurrent
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.artist?.trim().isNotEmpty == true
                          ? item.artist!
                          : item.projectId != null
                              ? '歌词工程'
                              : item.isRemoteStream
                                  ? '桌面音乐库'
                                  : '本地音乐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: _CurrentBadge(),
                ),
              IconButton(
                tooltip: isCurrent ? '从队列移除并播放下一首' : '从队列移除',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueArtwork extends StatelessWidget {
  final PlaybackItem item;

  const _QueueArtwork({required this.item});

  @override
  Widget build(BuildContext context) {
    final rawLocal = item.artworkPath?.trim().isNotEmpty == true
        ? item.artworkPath!.trim()
        : item.audioAsset.thumbnailPath?.trim();
    final file = rawLocal == null ? null : File(rawLocal);
    final hasArtwork = file != null && file.existsSync();
    final rawRemote = item.audioAsset.metadata['remoteArtworkUri'];
    final remote = rawRemote is String ? Uri.tryParse(rawRemote.trim()) : null;
    final validRemote = remote != null &&
        (remote.scheme == 'http' || remote.scheme == 'https');

    final fallback = Icon(
      item.isRemoteStream ? Icons.cloud_rounded : Icons.music_note_rounded,
      size: 18,
      color: AppColors.textSecondary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Container(
        width: 38,
        height: 38,
        color: AppColors.bgSurface,
        child: hasArtwork
            ? Image.file(file!, fit: BoxFit.cover)
            : validRemote
                ? Image.network(
                    remote.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  )
                : fallback,
      ),
    );
  }
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withAlpha(28),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        '当前',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.queue_music_rounded,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '播放队列为空',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
