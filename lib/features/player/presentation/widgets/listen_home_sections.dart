import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../domain/models/play_history.dart';
import 'listen_home_text.dart';
import 'now_playing_listener.dart';

// The lower part of 听歌 (D-041): 播放全部 / 随机播放, the lyric nudge,
// 最近播放 and the library shortcuts.

/// 播放全部 and 随机播放 over the whole library.
class ListenHomeQuickPlayRow extends StatelessWidget {
  const ListenHomeQuickPlayRow({
    super.key,
    required this.enabled,
    required this.onPlayAll,
    required this.onShuffle,
  });

  final bool enabled;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final height = math.max(
      52.0,
      AppResponsive.of(context).minimumInteractiveExtent,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: ListenHomeKeys.playAll,
            style: AppTheme.vinylFilled.copyWith(
              minimumSize: WidgetStatePropertyAll(Size(0, height)),
              shape: WidgetStatePropertyAll(shape),
            ),
            onPressed: enabled ? onPlayAll : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(ListenHomeText.playAllLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.tonalIcon(
            key: ListenHomeKeys.shuffle,
            style: FilledButton.styleFrom(
              minimumSize: Size(0, height),
              shape: shape,
            ),
            onPressed: enabled ? onShuffle : null,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text(ListenHomeText.shuffleLabel),
          ),
        ),
      ],
    );
  }
}

/// Offers lyric import for the song playing when it has none.
class ListenHomeLyricsNudge extends StatelessWidget {
  const ListenHomeLyricsNudge({
    super.key,
    required this.title,
    required this.onImport,
  });

  final String title;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.vinylSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_rounded, color: AppColors.vinylAccent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '「$title」还没有歌词',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '联网获取、导入 LRC / TXT 文件或粘贴纯文本歌词。',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onImport,
              child: const Text(ListenHomeText.importLyricsLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最近播放: a song row per play, marking the one on; or a line saying
/// where plays will show up.
class ListenHomeRecentShelf extends StatelessWidget {
  const ListenHomeRecentShelf({
    super.key,
    required this.recent,
    required this.loading,
    required this.gutter,
    required this.nowPlaying,
    required this.onResume,
  });

  final List<PlayHistory> recent;
  final bool loading;
  final double gutter;
  final NowPlaying nowPlaying;
  final ValueChanged<PlayHistory> onResume;

  /// The row's second line: the artist, and where listening stopped.
  static String subtitleOf(PlayHistory history) {
    final artist = history.artist?.trim();
    final position = history.lastPosition;
    return [
      artist == null || artist.isEmpty ? '本地音乐' : artist,
      if (position != null && position > Duration.zero)
        '听到 ${_clock(position)}',
    ].join(' · ');
  }

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      final textTheme = Theme.of(context).textTheme;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Text(
          loading ? ListenHomeText.recentLoading : ListenHomeText.recentEmpty,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: math.max(0, gutter - AppSpacing.sm),
      ),
      child: Column(
        children: [
          for (final history in recent)
            AppSongRow(
              key: ListenHomeKeys.recent(history.id),
              title: history.name,
              subtitle: subtitleOf(history),
              artwork: AppArtwork(
                path: history.artworkPath,
                borderRadius: AppArtwork.rowRadius,
              ),
              playback: nowPlaying.playbackForPath(history.filePath),
              semanticHint: ListenHomeText.recentHint,
              onTap: () => onResume(history),
            ),
        ],
      ),
    );
  }
}

/// A section heading, read out as a header.
class ListenHomeSectionTitle extends StatelessWidget {
  const ListenHomeSectionTitle(this.title, {super.key, required this.padding});

  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// One library section the home can jump to.
class _Shortcut {
  const _Shortcut(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

/// The five library sections as a row of record-sleeve tiles.
class ListenHomeLibraryShortcuts extends StatelessWidget {
  const ListenHomeLibraryShortcuts({
    super.key,
    required this.gutter,
    required this.songCount,
    required this.onOpen,
  });

  final double gutter;
  final int songCount;
  final ValueChanged<String> onOpen;

  static const List<_Shortcut> _shortcuts = [
    _Shortcut('歌曲', Icons.music_note_rounded, Routes.library),
    _Shortcut('艺人', Icons.person_rounded, Routes.libraryArtists),
    _Shortcut('专辑', Icons.album_rounded, Routes.libraryAlbums),
    _Shortcut('收藏', Icons.favorite_rounded, Routes.collections),
    _Shortcut('歌单', Icons.queue_music_rounded, Routes.playlists),
  ];

  static const double tileWidth = 96;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        itemCount: _shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final shortcut = _shortcuts[index];
          final caption = index == 0 ? '$songCount 首' : null;
          return SizedBox(
            width: tileWidth,
            child: AppTapTarget(
              label: AppTapTarget.join([shortcut.label, caption]),
              hint: '打开',
              onTap: () => onOpen(shortcut.route),
              child: Material(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onOpen(shortcut.route),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.vinylSurfaceHigh,
                        ),
                        child: Icon(
                          shortcut.icon,
                          color: AppColors.vinylAccent,
                          size: AppSpacing.iconSizeMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        shortcut.label,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption,
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
