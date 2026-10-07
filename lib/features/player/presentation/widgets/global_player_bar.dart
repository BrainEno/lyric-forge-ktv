import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import 'local_collection_actions.dart';
import 'local_media_metadata_dialog.dart';
import 'local_song_lyrics_import_action.dart';
import 'playback_mode_controls.dart';
import 'playback_queue_panel.dart';

class GlobalPlayerBar extends StatefulWidget {
  const GlobalPlayerBar({super.key});

  @override
  State<GlobalPlayerBar> createState() => _GlobalPlayerBarState();
}

class _GlobalPlayerBarState extends State<GlobalPlayerBar> {
  late final PlaybackSessionService _session;
  late final AudioPlayerService _audio;
  bool _queueExpanded = false;

  @override
  void initState() {
    super.initState();
    _session = ServiceLocatorGlobal.I.playbackSessionService;
    _audio = ServiceLocatorGlobal.I.audioPlayerService;
  }

  Future<void> _addToPlaylist(BuildContext context, PlaybackItem item) async {
    if (item.isRemoteStream) return;
    final playlist = await showAddToLocalPlaylistDialog(
      context,
      sourcePath: item.audioAsset.originalPath,
      title: item.title,
    );
    if (!context.mounted || playlist == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入“${playlist.name}”')),
    );
  }

  Future<void> _handleSongAction(
    BuildContext context,
    PlaybackItem item,
    String value,
  ) async {
    switch (value) {
      case 'library':
        Navigator.pushNamed(context, Routes.library);
        return;
      case 'collections':
        Navigator.pushNamed(context, Routes.collections);
        return;
      case 'playlist':
        if (!item.isRemoteStream) await _addToPlaylist(context, item);
        return;
      case 'lyrics':
        if (!item.isRemoteStream) {
          await importLyricsForLocalPlaybackItem(context, item);
        }
        return;
      case 'edit':
        if (!item.isRemoteStream) {
          await showLocalMediaMetadataDialog(context, item);
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppResponsive.isDesktopTarget()) return const SizedBox.shrink();

    return StreamBuilder<PlaybackSessionState>(
      stream: _session.stateStream,
      initialData: _session.currentState,
      builder: (context, sessionSnapshot) {
        final session = sessionSnapshot.data ?? const PlaybackSessionState();
        final item = session.currentItem;
        if (item == null) {
          if (_queueExpanded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _queueExpanded = false);
            });
          }
          return const SizedBox.shrink();
        }

        final localSong = item.projectId == null && !item.isRemoteStream;

        return StreamBuilder<PlaybackState>(
          stream: _audio.stateStream,
          initialData: _audio.currentState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? const PlaybackState.idle();

            return LayoutBuilder(
              builder: (context, constraints) {
                final layout = AppResponsive.fromConstraints(constraints);
                final minimal = layout.isCompact;
                final compact = layout.isCompactOrMedium;
                final queueHeight = layout.isShort ? 220.0 : 320.0;
                final queueMaxWidth = layout.isExtraWideDesktop ? 640.0 : 560.0;

                return Material(
                  color: AppColors.bgElevated,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 180),
                        crossFadeState: _queueExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.pageGutter,
                            vertical: AppSpacing.sm,
                          ),
                          color: AppColors.bgBase,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: queueMaxWidth),
                              child: PlaybackQueuePanel(
                                session: _session,
                                height: queueHeight,
                                showBorder: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                      LinearProgressIndicator(
                        value: playback.duration == null
                            ? 0.0
                            : playback.progressPercent.clamp(0.0, 1.0).toDouble(),
                        minHeight: 2,
                        backgroundColor: AppColors.bgHighlight,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.pageGutter,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                              onTap: () => Navigator.pushNamed(context, Routes.nowPlaying),
                              child: _Artwork(
                                item: item,
                                extent: minimal ? 40 : 48,
                              ),
                            ),
                            SizedBox(width: minimal ? AppSpacing.sm : AppSpacing.md),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                                onTap: () => Navigator.pushNamed(context, Routes.nowPlaying),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      if (!compact) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.artist?.trim().isNotEmpty == true
                                              ? item.artist!
                                              : item.projectId != null
                                                  ? '歌词工程'
                                                  : item.isRemoteStream
                                                      ? '远程音乐'
                                                      : '本地音乐',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: AppColors.textTertiary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (!compact)
                              IconButton(
                                tooltip: '音乐库',
                                onPressed: () => Navigator.pushNamed(context, Routes.library),
                                icon: const Icon(Icons.library_music_rounded),
                              ),
                            if (!compact)
                              IconButton(
                                tooltip: '收藏与播放列表',
                                onPressed: () => Navigator.pushNamed(context, Routes.collections),
                                icon: const Icon(Icons.collections_bookmark_outlined),
                              ),
                            if (localSong)
                              LocalFavoriteButton(
                                key: ValueKey('favorite:${item.audioAsset.originalPath}'),
                                sourcePath: item.audioAsset.originalPath,
                              ),
                            if (localSong && !compact) ...[
                              IconButton(
                                tooltip: '加入播放列表',
                                onPressed: () => _addToPlaylist(context, item),
                                icon: const Icon(Icons.playlist_add_rounded),
                              ),
                              IconButton(
                                tooltip: item.hasLyrics ? '打开歌词' : '导入歌词文件',
                                onPressed: () => importLyricsForLocalPlaybackItem(context, item),
                                icon: Icon(
                                  item.hasLyrics
                                      ? Icons.lyrics_rounded
                                      : Icons.file_upload_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: '编辑歌曲资料与封面',
                                onPressed: () => showLocalMediaMetadataDialog(context, item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                            if (localSong && compact)
                              PopupMenuButton<String>(
                                tooltip: '更多歌曲操作',
                                onSelected: (value) => _handleSongAction(context, item, value),
                                itemBuilder: (_) => [
                                  if (minimal)
                                    const PopupMenuItem(
                                      value: 'library',
                                      child: Text('音乐库'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'collections',
                                    child: Text('收藏与播放列表'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'playlist',
                                    child: Text('加入播放列表'),
                                  ),
                                  PopupMenuItem(
                                    value: 'lyrics',
                                    child: Text(item.hasLyrics ? '打开歌词' : '导入歌词文件'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑歌曲资料与封面'),
                                  ),
                                ],
                                icon: const Icon(Icons.more_horiz_rounded),
                              ),
                            if (!compact)
                              PlaybackModeControls(
                                session: _session,
                                compact: true,
                              ),
                            if (!minimal)
                              IconButton(
                                tooltip: '上一首 / 重新开始',
                                onPressed: session.canSkipPrevious
                                    ? _session.skipPrevious
                                    : null,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                            SizedBox(
                              width: minimal ? 40 : 42,
                              height: minimal ? 40 : 42,
                              child: IconButton(
                                tooltip: playback.isPlaying ? '暂停' : '播放',
                                onPressed: playback.isBuffering
                                    ? null
                                    : _session.togglePlayPause,
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.pureWhite,
                                  foregroundColor: AppColors.pureBlack,
                                ),
                                icon: playback.isBuffering
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.pureBlack,
                                        ),
                                      )
                                    : Icon(
                                        playback.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                      ),
                              ),
                            ),
                            if (!minimal)
                              IconButton(
                                tooltip: '下一首',
                                onPressed: session.canSkipNext
                                    ? _session.skipNext
                                    : null,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                            SizedBox(width: minimal ? AppSpacing.xs : AppSpacing.sm),
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _queueExpanded = !_queueExpanded,
                              ),
                              icon: Icon(
                                _queueExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.queue_music_rounded,
                                size: 20,
                              ),
                              label: Text(
                                compact
                                    ? '${session.queue.length}'
                                    : '队列 ${session.queue.length}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final PlaybackItem item;
  final double extent;

  const _Artwork({
    required this.item,
    this.extent = 48,
  });

  @override
  Widget build(BuildContext context) {
    final localPath = item.artworkPath?.trim().isNotEmpty == true
        ? item.artworkPath!.trim()
        : item.audioAsset.thumbnailPath?.trim();
    final file = localPath == null ? null : File(localPath);
    final hasArtwork = file != null && file.existsSync();
    final rawRemote = item.audioAsset.metadata['remoteArtworkUri'];
    final remote = rawRemote is String ? Uri.tryParse(rawRemote.trim()) : null;
    final hasRemote = item.isRemoteStream &&
        remote != null &&
        (remote.scheme == 'http' || remote.scheme == 'https');

    final fallback = Icon(
      item.isRemoteStream ? Icons.cloud_rounded : Icons.music_note_rounded,
      color: AppColors.textSecondary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Container(
        width: extent,
        height: extent,
        color: AppColors.bgSurface,
        child: hasArtwork
            ? Image.file(file!, fit: BoxFit.cover)
            : hasRemote
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
