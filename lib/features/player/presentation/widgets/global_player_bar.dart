import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) return const SizedBox.shrink();

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

        return StreamBuilder<PlaybackState>(
          stream: _audio.stateStream,
          initialData: _audio.currentState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? const PlaybackState.idle();

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
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      color: AppColors.bgBase,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: PlaybackQueuePanel(
                            session: _session,
                            height: 320,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 900;
                        return Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                              onTap: () => Navigator.pushNamed(context, Routes.nowPlaying),
                              child: _Artwork(path: item.artworkPath),
                            ),
                            const SizedBox(width: AppSpacing.md),
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
                            IconButton(
                              tooltip: '音乐库',
                              onPressed: () => Navigator.pushNamed(context, Routes.library),
                              icon: const Icon(Icons.library_music_rounded),
                            ),
                            if (!compact)
                              IconButton(
                                tooltip: '收藏与播放列表',
                                onPressed: () =>
                                    Navigator.pushNamed(context, Routes.collections),
                                icon: const Icon(Icons.collections_bookmark_outlined),
                              ),
                            if (item.projectId == null) ...[
                              LocalFavoriteButton(
                                key: ValueKey('favorite:${item.audioAsset.originalPath}'),
                                sourcePath: item.audioAsset.originalPath,
                              ),
                              if (!compact) ...[
                                IconButton(
                                  tooltip: '加入播放列表',
                                  onPressed: () => _addToPlaylist(context, item),
                                  icon: const Icon(Icons.playlist_add_rounded),
                                ),
                                IconButton(
                                  tooltip: item.hasLyrics ? '打开歌词' : '导入歌词文件',
                                  onPressed: () {
                                    importLyricsForLocalPlaybackItem(context, item);
                                  },
                                  icon: Icon(
                                    item.hasLyrics
                                        ? Icons.lyrics_rounded
                                        : Icons.file_upload_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '编辑歌曲资料与封面',
                                  onPressed: () {
                                    showLocalMediaMetadataDialog(context, item);
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ] else
                                PopupMenuButton<String>(
                                  tooltip: '更多歌曲操作',
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'collections':
                                        Navigator.pushNamed(context, Routes.collections);
                                        return;
                                      case 'playlist':
                                        await _addToPlaylist(context, item);
                                        return;
                                      case 'lyrics':
                                        await importLyricsForLocalPlaybackItem(context, item);
                                        return;
                                      case 'edit':
                                        await showLocalMediaMetadataDialog(context, item);
                                        return;
                                    }
                                  },
                                  itemBuilder: (_) => [
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
                            ],
                            IconButton(
                              tooltip: '上一首 / 重新开始',
                              onPressed: session.canSkipPrevious
                                  ? _session.skipPrevious
                                  : null,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            SizedBox(
                              width: 42,
                              height: 42,
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
                            const SizedBox(width: AppSpacing.xs),
                            IconButton(
                              tooltip: '下一首',
                              onPressed: session.canSkipNext
                                  ? _session.skipNext
                                  : null,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                            const SizedBox(width: AppSpacing.sm),
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? path;

  const _Artwork({this.path});

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasArtwork = file != null && file.existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      child: Container(
        width: 48,
        height: 48,
        color: AppColors.bgSurface,
        child: hasArtwork
            ? Image.file(file!, fit: BoxFit.cover)
            : const Icon(
                Icons.music_note_rounded,
                color: AppColors.textSecondary,
              ),
      ),
    );
  }
}
