import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_scope.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../../core/widgets/undo_snack_bar.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/services/playback_session_service.dart';
import 'playback_action_feedback.dart';
import 'playback_artwork.dart';
import 'playback_mode_controls.dart';
import 'playback_queue_semantics.dart';
import 'playback_queue_playlist_action.dart';

class PlaybackQueuePanel extends StatelessWidget {
  final PlaybackSessionService session;
  final PlaybackSessionState? sessionState;

  /// Only needed by "save queue as playlist"; required so the panel cannot fall
  /// back to the app-wide locator when a caller forgets it.
  final LocalMediaCollectionRepository collectionRepository;
  final double height;
  final bool allowClearAll;
  final bool showBorder;

  const PlaybackQueuePanel({
    super.key,
    required this.session,
    this.sessionState,
    required this.collectionRepository,
    this.height = 360,
    this.allowClearAll = false,
    this.showBorder = true,
  });

  Future<void> _saveQueue(
    BuildContext context,
    PlaybackSessionState state,
  ) async {
    // The panel also opens from the desktop player bar, which is chrome
    // outside the navigator; the dialog needs the navigator's context.
    final host = AppChromeScope.contextOf(context);
    final result = await savePlaybackQueueToPlaylist(
      host,
      state,
      repository: collectionRepository,
    );
    if (!host.mounted || result == null) return;

    final skipped = result.skippedCount > 0
        ? '，跳过 ${result.skippedCount} 个远程、工程或重复队列项'
        : '';
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(
        content: Text(
          '已将 ${result.savedCount} 首本地歌曲保存到“${result.playlistName}”$skipped',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providedState = sessionState;
    if (providedState != null) {
      return _buildForState(context, providedState);
    }
    return StreamBuilder<PlaybackSessionState>(
      stream: session.stateStream,
      initialData: session.currentState,
      builder: (context, snapshot) => _buildForState(
        context,
        snapshot.data ?? const PlaybackSessionState(),
      ),
    );
  }

  void _removeWithUndo(
    BuildContext context,
    PlaybackSessionState state,
    int index,
  ) => _removeQueueItemWithUndo(context, session, state, index);

  void _clearWithUndo(
    BuildContext context,
    PlaybackSessionState state, {
    required bool keepCurrent,
  }) => _clearQueueWithUndo(context, session, state, keepCurrent: keepCurrent);

  Widget _buildForState(BuildContext context, PlaybackSessionState state) {
    final savableQueueCount = localQueuePlaylistPaths(state).length;
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
            onSaveQueue: savableQueueCount > 0
                ? () => _saveQueue(context, state)
                : null,
            onClearUpcoming: state.upcomingCount > 0
                ? () => _clearWithUndo(context, state, keepCurrent: true)
                : null,
            onClearAll: state.queue.isNotEmpty && allowClearAll
                ? () => _clearWithUndo(context, state, keepCurrent: false)
                : null,
          ),
          Divider(height: 1, color: AppColors.borderMuted),
          Expanded(
            child: state.queue.isEmpty
                ? const _EmptyQueue()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    buildDefaultDragHandles: false,
                    itemCount: state.queue.length,
                    // The new index already accounts for the moved row.
                    onReorderItem: (oldIndex, newIndex) {
                      if (newIndex < 0 || newIndex >= state.queue.length) {
                        return;
                      }
                      session.moveItem(oldIndex, newIndex);
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
                        onRemove: () => _removeWithUndo(context, state, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Takes one song off the queue and offers 撤销 (D-064).
Future<void> _removeQueueItemWithUndo(
  BuildContext context,
  PlaybackSessionService session,
  PlaybackSessionState state,
  int index,
) async {
  if (index < 0 || index >= state.queue.length) return;
  final messenger = ScaffoldMessenger.of(context);
  final item = state.queue[index];
  await session.removeAt(index);
  showUndoSnackBar(
    messenger,
    message: '已从播放队列移除“${item.title}”',
    onUndo: () async {
      await restoreQueueItems(session, [(index: index, item: item)]);
      return null;
    },
  );
}

/// Clears the queue — all of it, or all but the current song — and offers
/// 撤销 (D-064).
Future<void> _clearQueueWithUndo(
  BuildContext context,
  PlaybackSessionService session,
  PlaybackSessionState state, {
  required bool keepCurrent,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final removed = [
    for (var index = 0; index < state.queue.length; index++)
      if (!keepCurrent || index != state.currentIndex)
        (index: index, item: state.queue[index]),
  ];
  await session.clearQueue(keepCurrent: keepCurrent);
  if (removed.isEmpty) return;
  showUndoSnackBar(
    messenger,
    message: keepCurrent
        ? '已清空待播的 ${removed.length} 首'
        : '已清空播放队列（${removed.length} 首）',
    onUndo: () async {
      await restoreQueueItems(session, removed);
      return null;
    },
  );
}

/// Puts [removed] songs back at their old places (D-064).
///
/// They are appended, then moved into place in ascending order, so each
/// lands where it was. With shuffle on, the session shuffles what it is
/// given, so only the songs come back, not their order. Restoring a cleared
/// queue does not start playback.
Future<void> restoreQueueItems(
  PlaybackSessionService session,
  List<({int index, PlaybackItem item})> removed,
) async {
  final ordered = [...removed]..sort((a, b) => a.index.compareTo(b.index));
  for (final entry in ordered) {
    await session.enqueue(entry.item);
  }
  if (session.currentState.shuffleEnabled) return;
  for (final entry in ordered) {
    final queue = session.currentState.queue;
    final at = queue.indexWhere((item) => item.id == entry.item.id);
    final target = entry.index.clamp(0, queue.length - 1).toInt();
    if (at >= 0 && at != target) await session.moveItem(at, target);
  }
}

class _QueueHeader extends StatelessWidget {
  final PlaybackSessionService session;
  final PlaybackSessionState state;
  final bool allowClearAll;
  final VoidCallback? onSaveQueue;
  final VoidCallback? onClearUpcoming;
  final VoidCallback? onClearAll;

  const _QueueHeader({
    required this.session,
    required this.state,
    required this.allowClearAll,
    required this.onSaveQueue,
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
              Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '播放队列',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: onSaveQueue == null ? '当前队列没有可保存的本地歌曲' : '保存队列到播放列表',
                onPressed: onSaveQueue,
                icon: const Icon(Icons.playlist_add_rounded),
                iconSize: 20,
              ),
              PlaybackModeControls(
                session: session,
                sessionState: state,
                compact: true,
              ),
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
              TextButton(onPressed: onClearUpcoming, child: const Text('清空待播')),
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

  /// The second line: artist, else where the song comes from.
  String get source => item.artist?.trim().isNotEmpty == true
      ? item.artist!
      : item.projectId != null
      ? '歌词工程'
      : item.isRemoteStream
      ? '桌面音乐库'
      : '本地音乐';

  /// The row is read as one button (audit A-04) and its label joins the
  /// node the reorderable list puts around each row, so 上移/下移 stay on
  /// the same stop. The remove button is left outside it, a stop of its own.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? AppColors.accent.withAlpha(16) : Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: AppTapTarget(
                  label: PlaybackQueueSemantics.row(
                    position: index + 1,
                    title: item.title,
                    source: source,
                    current: isCurrent,
                  ),
                  hint: isCurrent ? null : PlaybackQueueSemantics.playHint,
                  selected: isCurrent,
                  onTap: onPlay,
                  container: false,
                  child: _QueueRowContent(
                    index: index,
                    item: item,
                    source: source,
                    isCurrent: isCurrent,
                  ),
                ),
              ),
              IconButton(
                tooltip: PlaybackQueueSemantics.removeTooltip(
                  current: isCurrent,
                ),
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

/// Everything of a queue row except its remove button.
class _QueueRowContent extends StatelessWidget {
  final int index;
  final PlaybackItem item;
  final String source;
  final bool isCurrent;

  const _QueueRowContent({
    required this.index,
    required this.item,
    required this.source,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xs),
            child: Icon(
              Icons.drag_indicator_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PlaybackArtwork(item: item, size: 38),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isCurrent) ...[
                    Icon(
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
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        if (isCurrent)
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xs),
            child: _CurrentBadge(),
          ),
      ],
    );
  }
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    return const AppBadge(
      label: '当前',
      tone: AppBadgeTone.accent,
      emphasized: true,
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.queue_music_rounded,
      title: '播放队列为空',
      density: AppEmptyStateDensity.panel,
    );
  }
}
