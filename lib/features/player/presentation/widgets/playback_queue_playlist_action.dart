import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/services/playback_session_service.dart';
import 'local_collection_actions.dart';

class QueuePlaylistSaveResult {
  final String playlistName;
  final int savedCount;
  final int skippedCount;

  const QueuePlaylistSaveResult({
    required this.playlistName,
    required this.savedCount,
    required this.skippedCount,
  });
}

/// Returns local-library paths that can safely be persisted in a local playlist.
///
/// Remote Media Hub streams and project-only queue entries are intentionally
/// excluded because local playlists are path-based and must remain reopenable
/// without depending on another device or project workspace.
List<String> localQueuePlaylistPaths(PlaybackSessionState state) {
  final seen = <String>{};
  final paths = <String>[];
  for (final item in state.queue) {
    if (item.isRemoteStream || item.projectId != null) continue;
    final path = item.audioAsset.originalPath.trim();
    if (path.isEmpty || !seen.add(path)) continue;
    paths.add(path);
  }
  return paths;
}

Future<QueuePlaylistSaveResult?> savePlaybackQueueToPlaylist(
  BuildContext context,
  PlaybackSessionState state, {
  LocalMediaCollectionRepository? repository,
}) async {
  final paths = localQueuePlaylistPaths(state);
  if (paths.isEmpty) return null;

  final collections =
      repository ?? ServiceLocatorGlobal.I.localMediaCollectionRepository;
  final playlists = await collections.getPlaylists();
  if (!context.mounted) return null;

  final selected = await showDialog<Object>(
    context: context,
    builder: (dialogContext) {
      final spec = AppResponsive.of(dialogContext);
      final media = MediaQuery.of(dialogContext);
      final availableHeight = media.size.height -
          media.viewInsets.bottom -
          spec.pageGutter * 2;
      final listMaxHeight = (availableHeight * (spec.isShort ? 0.46 : 0.58))
          .clamp(160.0, 420.0)
          .toDouble();

      return AlertDialog(
        insetPadding: EdgeInsets.all(spec.pageGutter),
        title: const Text('保存播放队列'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: spec.isCompact
                ? (spec.width - spec.pageGutter * 2)
                    .clamp(260.0, 460.0)
                    .toDouble()
                : 460,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '可保存 ${paths.length} 首本地歌曲。远程串流和歌词工程不会写入本地播放列表。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('还没有播放列表。可以直接新建一个。'),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: listMaxHeight),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        minTileHeight: spec.minimumInteractiveExtent,
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${playlist.sourcePaths.length} 首歌曲'),
                        onTap: () => Navigator.pop(dialogContext, playlist),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            child: const Text('取消'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              const _CreateQueuePlaylistIntent(),
            ),
            style: TextButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(spec.isCompact ? '新建' : '新建播放列表'),
          ),
        ],
      );
    },
  );

  if (!context.mounted || selected == null) return null;

  LocalPlaylist? playlist;
  if (selected is LocalPlaylist) {
    playlist = selected;
  } else if (selected is _CreateQueuePlaylistIntent) {
    playlist = await showCreateLocalPlaylistDialog(
      context,
      repository: collections,
    );
  }
  if (playlist == null) return null;

  final updated = await collections.addToPlaylist(playlist.id, paths);
  final skipped = state.queue.length - paths.length;
  return QueuePlaylistSaveResult(
    playlistName: updated.name,
    savedCount: paths.length,
    skippedCount: skipped < 0 ? 0 : skipped,
  );
}

class _CreateQueuePlaylistIntent {
  const _CreateQueuePlaylistIntent();
}
