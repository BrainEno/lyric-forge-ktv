import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../../core/widgets/app_vinyl_disc.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import 'listen_home_text.dart';
import 'playback_action_feedback.dart';
import 'playback_artwork.dart';
import 'player_bar_semantics.dart';
import 'seekable_progress_bar.dart';

// The top of 听歌 (D-041): the header, then the record that is on or, with
// nothing playing, a still record and a way to start.

/// The page title, the library size and a search shortcut.
class ListenHomeHeader extends StatelessWidget {
  const ListenHomeHeader({
    super.key,
    required this.songCount,
    required this.loading,
    required this.onSearch,
    this.searchesEverything = false,
    this.onImport,
  });

  final int songCount;
  final bool loading;
  final VoidCallback onSearch;

  /// [onSearch] opens the global search rather than the library.
  final bool searchesEverything;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  ListenHomeText.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                loading ? '离线播放' : '离线播放 · $songCount 首本地歌曲',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (onImport != null)
          IconButton(
            key: ListenHomeKeys.import,
            tooltip: ListenHomeText.importMediaLabel,
            onPressed: onImport,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        IconButton(
          key: ListenHomeKeys.search,
          tooltip: searchesEverything ? '搜索歌曲、歌单和歌词' : '搜索音乐库',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }
}

/// Edge of the hero record on a page [width] wide: most of a phone's width,
/// capped so it does not fill a tablet.
double _discSizeFor(double width) => math.min(width * 0.62, 280);

/// The record that is on, its title and its transport.
class ListenHomePlayingHero extends StatelessWidget {
  const ListenHomePlayingHero({
    super.key,
    required this.item,
    required this.isPlaying,
    required this.dependencies,
    required this.onOpen,
  });

  final PlaybackItem item;
  final bool isPlaying;
  final LocalLibraryDependencies dependencies;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = dependencies.playbackSession;
    final audio = dependencies.audioPlayer;
    final subtitle = PlayerBarSemantics.subtitleFor(
      item,
      projectLabel: '有歌词',
      remoteLabel: '桌面音乐库',
      localLabel: '本地音乐',
    );
    final discSize = _discSizeFor(MediaQuery.sizeOf(context).width);

    return Column(
      children: [
        AppTapTarget(
          label: PlayerBarSemantics.nowPlaying(item.title, subtitle),
          hint: ListenHomeText.openPlayerHint,
          onTap: onOpen,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onOpen,
            child: AppVinylDisc(
              size: discSize,
              spinning: isPlaying,
              glow: true,
              label: PlaybackArtwork(item: item, borderRadius: 0),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        StreamBuilder<PlaybackState>(
          stream: audio.stateStream,
          initialData: audio.currentState,
          builder: (context, snapshot) {
            final playback = snapshot.data ?? const PlaybackState.idle();
            final busy = PlayerBarSemantics.isBusy(playback);
            final state = session.currentState;
            return Column(
              children: [
                SeekableProgressBar(
                  state: playback,
                  onSeek: session.seek,
                  compact: true,
                  activeColor: AppColors.vinylAccent,
                  thumbColor: AppColors.vinylAccent,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一首',
                      iconSize: AppSpacing.iconSizeLarge,
                      onPressed: state.canSkipPrevious
                          ? () => runPlaybackActionWithFeedback(
                              context,
                              session.skipPrevious,
                            )
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox.square(
                      dimension: 68,
                      child: IconButton(
                        tooltip: PlayerBarSemantics.playPause(playback),
                        iconSize: AppSpacing.iconSizeLarge,
                        style: AppTheme.vinylPlayDisc,
                        onPressed: busy
                            ? null
                            : () => runPlaybackActionWithFeedback(
                                context,
                                session.togglePlayPause,
                              ),
                        icon: busy
                            ? const AppButtonSpinner(size: 24)
                            : Icon(
                                playback.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    IconButton(
                      tooltip: '下一首',
                      iconSize: AppSpacing.iconSizeLarge,
                      onPressed: state.canSkipNext
                          ? () => runPlaybackActionWithFeedback(
                              context,
                              session.skipNext,
                            )
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A still record and a way to start, when nothing is loaded.
class ListenHomeIdleHero extends StatelessWidget {
  const ListenHomeIdleHero({
    super.key,
    required this.hasSongs,
    required this.songCount,
    required this.onShuffle,
    required this.onOpenLibrary,
    this.onImport,
  });

  final bool hasSongs;
  final int songCount;
  final VoidCallback onShuffle;
  final VoidCallback onOpenLibrary;

  /// 导入音频或视频 on a phone (D-056); leads when the library is empty.
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final layout = AppResponsive.of(context);
    final minimum = Size(0, layout.minimumInteractiveExtent);
    final discSize = _discSizeFor(MediaQuery.sizeOf(context).width) * 0.8;

    return Column(
      children: [
        AppVinylDisc(size: discSize, glow: true),
        const SizedBox(height: AppSpacing.lg),
        Text(
          ListenHomeText.idleTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hasSongs
              ? '从 $songCount 首本地歌曲里挑一首，或者随便听听。'
              : onImport != null
              ? '先把歌曲放进音乐库：从“文件”或相册导入音频、视频，或从电脑传过来。'
              : '先把歌曲放进音乐库：添加手机里的音乐文件夹，或从电脑传过来。',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: hasSongs
              ? [
                  FilledButton.icon(
                    style: AppTheme.vinylFilled.copyWith(
                      minimumSize: WidgetStatePropertyAll(minimum),
                    ),
                    onPressed: onShuffle,
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text(ListenHomeText.shuffleLabel),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: minimum),
                    onPressed: onOpenLibrary,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text(ListenHomeText.openLibraryLabel),
                  ),
                ]
              : [
                  if (onImport != null)
                    FilledButton.icon(
                      key: ListenHomeKeys.idleImport,
                      style: AppTheme.vinylFilled.copyWith(
                        minimumSize: WidgetStatePropertyAll(minimum),
                      ),
                      onPressed: onImport,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(ListenHomeText.importMediaLabel),
                    )
                  else
                    FilledButton.icon(
                      style: AppTheme.vinylFilled.copyWith(
                        minimumSize: WidgetStatePropertyAll(minimum),
                      ),
                      onPressed: onOpenLibrary,
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text(ListenHomeText.openLibraryLabel),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: minimum),
                    onPressed: () =>
                        TransferEntry.open(context, desktop: false),
                    icon: const Icon(TransferEntry.icon),
                    label: const Text(ListenHomeText.transferLabel),
                  ),
                ],
        ),
      ],
    );
  }
}
