import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_catalog_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../local_library_explorer_song.dart';
import 'library_lyrics_link_text.dart';
import 'local_library_semantics.dart';
import 'now_playing_listener.dart';

class LocalLibraryExplorerGrid extends StatelessWidget {
  final List<LocalLibraryExplorerSong> songs;
  final ValueChanged<LocalLibraryExplorerSong> onPlay;
  final ValueChanged<LocalLibraryExplorerSong> onEnqueue;
  final ValueChanged<LocalLibraryExplorerSong> onEdit;
  final ValueChanged<LocalLibraryExplorerSong> onLyrics;
  final ValueChanged<LocalLibraryExplorerSong>? onUnpair;
  final ValueChanged<LocalLibraryExplorerSong> onRelink;
  final ValueChanged<LocalLibraryExplorerSong> onRemove;

  const LocalLibraryExplorerGrid({
    super.key,
    required this.songs,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: AppCatalogCard.gridDelegateFor(layout),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final unpair = onUnpair;
            return _ExplorerCard(
              song: song,
              compact: layout.isCompact,
              onPlay: () => onPlay(song),
              onEnqueue: () => onEnqueue(song),
              onEdit: () => onEdit(song),
              onLyrics: () => onLyrics(song),
              onUnpair: unpair == null ? null : () => unpair(song),
              onRelink: () => onRelink(song),
              onRemove: () => onRemove(song),
            );
          },
        );
      },
    );
  }
}

class LocalLibraryExplorerList extends StatelessWidget {
  final List<LocalLibraryExplorerSong> songs;
  final NowPlaying nowPlaying;
  final ValueChanged<LocalLibraryExplorerSong> onPlay;
  final ValueChanged<LocalLibraryExplorerSong> onEnqueue;
  final ValueChanged<LocalLibraryExplorerSong> onEdit;
  final ValueChanged<LocalLibraryExplorerSong> onLyrics;
  final ValueChanged<LocalLibraryExplorerSong>? onUnpair;
  final ValueChanged<LocalLibraryExplorerSong> onRelink;
  final ValueChanged<LocalLibraryExplorerSong> onRemove;

  const LocalLibraryExplorerList({
    super.key,
    required this.songs,
    required this.nowPlaying,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: layout.isCompact ? AppSpacing.sm : layout.pageGutter,
        vertical: AppSpacing.sm,
      ),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final song = songs[index];
        final unpair = onUnpair;
        final menu = _SongMenuCallbacks(
          onEnqueue: () => onEnqueue(song),
          onEdit: () => onEdit(song),
          onLyrics: () => onLyrics(song),
          onUnpair: unpair == null ? null : () => unpair(song),
          onRelink: () => onRelink(song),
          onRemove: () => onRemove(song),
        );
        return AppSongRow(
          key: ValueKey('library-song:${song.entry.sourcePath}'),
          title: song.title,
          subtitle: song.secondary,
          unavailable: !song.playable,
          unavailableLabel: '文件不可用 · 引用仍保留',
          artwork: song.playable
              ? AppArtwork(
                  path: song.artworkPath,
                  borderRadius: AppArtwork.rowRadius,
                )
              : AppArtwork.missing(
                  path: song.artworkPath,
                  borderRadius: AppArtwork.rowRadius,
                ),
          badges: [
            if (song.hasLyrics)
              const AppSongRowBadge(icon: Icons.lyrics_rounded),
            if (song.hasUserOverride)
              const AppSongRowBadge(icon: Icons.edit_note_rounded),
          ],
          playback: song.playable
              ? nowPlaying.playbackForPath(song.entry.sourcePath)
              : AppSongRowPlayback.none,
          onTap: () => onPlay(song),
          semanticLabel: _songLabel(song),
          semanticHint: LocalLibrarySemantics.playHint,
          semanticActions: _songActions(song, menu),
          trailing: _SongMenu(
            song: song,
            onEnqueue: menu.onEnqueue,
            onEdit: menu.onEdit,
            onLyrics: menu.onLyrics,
            onUnpair: menu.onUnpair,
            onRelink: menu.onRelink,
            onRemove: menu.onRemove,
          ),
        );
      },
    );
  }
}

/// The ⋯ menu's callbacks for one song, shared by the menu and the
/// screen-reader actions of its card or row.
class _SongMenuCallbacks {
  const _SongMenuCallbacks({
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;
}

/// The format, edit and lyrics notes of [song], read in its label and shown
/// as a card's last line.
List<String> _songDetails(LocalLibraryExplorerSong song) => [
  [
    if (song.entry.embeddedTrackNumber != null)
      '#${song.entry.embeddedTrackNumber}',
    song.entry.format.toUpperCase(),
  ].join(' · '),
  if (song.hasUserOverride) '已编辑',
  if (song.hasLyrics) song.lyricsLabel,
];

/// What a screen reader hears for [song], on a card and on a row alike.
String _songLabel(LocalLibraryExplorerSong song) => LocalLibrarySemantics.songCard(
  title: song.title,
  artist: song.artist,
  playable: song.playable,
  details: _songDetails(song),
);

/// The ⋯ menu's entries as screen-reader actions, in menu order and with
/// the menu's wording (audit A-04).
Map<String, VoidCallback?> _songActions(
  LocalLibraryExplorerSong song,
  _SongMenuCallbacks menu,
) => {
  if (song.playable) '加入播放队列': menu.onEnqueue,
  if (song.playable) '编辑资料与封面': menu.onEdit,
  if (song.playable) (song.hasLyrics ? '打开歌词' : '导入歌词'): menu.onLyrics,
  if (song.hasAutoPairedLyrics)
    LibraryLyricsLinkText.unpairAction: menu.onUnpair,
  if (!song.playable) '重新定位文件': menu.onRelink,
  '从音乐库移除': menu.onRemove,
};

class _ExplorerCard extends StatelessWidget {
  final LocalLibraryExplorerSong song;
  final bool compact;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;

  const _ExplorerCard({
    required this.song,
    required this.compact,
    required this.onPlay,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppCatalogCard(
      semanticLabel: _songLabel(song),
      semanticHint: LocalLibrarySemantics.playHint,
      enabled: song.playable,
      unavailable: !song.playable,
      onTap: onPlay,
      semanticActions: semanticActions,
      compact: compact,
      artwork: song.playable
          ? AppArtwork(
              path: song.artworkPath,
              borderRadius: AppArtwork.tileRadius,
            )
          : AppArtwork.missing(path: song.artworkPath),
      title: song.title,
      titleTrailing: _SongMenu(
        song: song,
        onEnqueue: onEnqueue,
        onEdit: onEdit,
        onLyrics: onLyrics,
        onUnpair: onUnpair,
        onRelink: onRelink,
        onRemove: onRemove,
      ),
      subtitle: song.playable ? (song.artist ?? '本地音乐') : '文件不可用',
      subtitleIsAlert: !song.playable,
      caption: _songDetails(
        song,
      ).where((value) => value.isNotEmpty).join(' · '),
    );
  }

  /// The ⋯ menu's entries as the card's screen-reader actions.
  Map<String, VoidCallback?> get semanticActions => _songActions(
    song,
    _SongMenuCallbacks(
      onEnqueue: onEnqueue,
      onEdit: onEdit,
      onLyrics: onLyrics,
      onUnpair: onUnpair,
      onRelink: onRelink,
      onRemove: onRemove,
    ),
  );
}

class _SongMenu extends StatelessWidget {
  final LocalLibraryExplorerSong song;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback? onUnpair;
  final VoidCallback onRelink;
  final VoidCallback onRemove;

  const _SongMenu({
    required this.song,
    required this.onEnqueue,
    required this.onEdit,
    required this.onLyrics,
    required this.onUnpair,
    required this.onRelink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'queue':
            onEnqueue();
            return;
          case 'edit':
            onEdit();
            return;
          case 'lyrics':
            onLyrics();
            return;
          case 'unpair':
            onUnpair?.call();
            return;
          case 'relink':
            onRelink();
            return;
          case 'remove':
            onRemove();
            return;
        }
      },
      itemBuilder: (_) => [
        if (song.playable)
          const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
        if (song.playable)
          const PopupMenuItem(value: 'edit', child: Text('编辑资料与封面')),
        if (song.playable)
          PopupMenuItem(
            value: 'lyrics',
            child: Text(song.hasLyrics ? '打开歌词' : '导入歌词'),
          ),
        if (song.hasAutoPairedLyrics && onUnpair != null)
          const PopupMenuItem(
            value: 'unpair',
            child: Text(LibraryLyricsLinkText.unpairAction),
          ),
        if (!song.playable)
          const PopupMenuItem(value: 'relink', child: Text('重新定位文件')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('从音乐库移除')),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class LocalLibraryExplorerNoResults extends StatelessWidget {
  const LocalLibraryExplorerNoResults({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search_off_rounded,
      title: '没有符合当前搜索或智能列表条件的歌曲',
    );
  }
}

class LocalLibraryExplorerEmptyState extends StatelessWidget {
  final VoidCallback onFiles;
  final VoidCallback? onFolder;

  /// The phone's 导入音频或视频 (D-056) leads instead of the folder.
  final bool importsMedia;

  const LocalLibraryExplorerEmptyState({
    super.key,
    required this.onFiles,
    required this.onFolder,
    this.importsMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final minimumSize = Size(
      layout.minimumInteractiveExtent,
      layout.minimumInteractiveExtent,
    );
    final folder = onFolder;
    if (importsMedia) {
      return AppEmptyState(
        density: AppEmptyStateDensity.hero,
        icon: Icons.library_music_rounded,
        title: '建立你的本地音乐库',
        message: '从“文件”或相册导入歌曲；视频会自动提取声音，保存成较小的音频文件。',
        actions: [
          FilledButton.icon(
            key: const ValueKey('library-import-media'),
            style: FilledButton.styleFrom(minimumSize: minimumSize),
            onPressed: onFiles,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入音频或视频'),
          ),
          if (folder != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: minimumSize),
              onPressed: folder,
              icon: const Icon(Icons.folder_rounded),
              label: const Text('添加音乐文件夹'),
            ),
        ],
      );
    }
    return AppEmptyState(
      density: AppEmptyStateDensity.hero,
      icon: Icons.library_music_rounded,
      title: '建立你的本地音乐库',
      message: '导入后自动读取标题、艺人、专辑和内嵌封面。',
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: minimumSize),
          onPressed: folder,
          icon: const Icon(Icons.folder_rounded),
          label: const Text('添加音乐文件夹'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: minimumSize),
          onPressed: onFiles,
          icon: const Icon(Icons.audio_file_rounded),
          label: const Text('添加音乐文件'),
        ),
      ],
    );
  }
}
