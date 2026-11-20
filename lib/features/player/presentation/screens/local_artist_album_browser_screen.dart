import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_catalog_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../widgets/local_collection_actions.dart';
import '../widgets/local_library_semantics.dart';
import '../widgets/now_playing_listener.dart';

enum LocalCatalogView { artists, albums }

class LocalArtistAlbumBrowserScreen extends StatefulWidget {
  final LocalCatalogView view;

  /// Supplied by `LocalMusicLibraryShell`.
  final LocalLibraryDependencies dependencies;

  const LocalArtistAlbumBrowserScreen({
    super.key,
    required this.view,
    required this.dependencies,
  });

  @override
  State<LocalArtistAlbumBrowserScreen> createState() =>
      _LocalArtistAlbumBrowserScreenState();
}

class _LocalArtistAlbumBrowserScreenState
    extends State<LocalArtistAlbumBrowserScreen> {
  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _metadata;
  late final PlaybackSessionService _session;

  List<_CatalogSong> _songs = const [];
  bool _loading = true;
  String? _error;
  String? _selectedArtist;
  String? _selectedAlbumKey;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _library = dependencies.libraryRepository;
    _metadata = dependencies.metadataRepository;
    _session = dependencies.playbackSession;
    _reload();
  }

  @override
  void didUpdateWidget(covariant LocalArtistAlbumBrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      setState(() {
        _selectedArtist = null;
        _selectedAlbumKey = null;
      });
      _reload();
    }
  }

  String _pathKey(String path) {
    final canonical = File(path).absolute.path;
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final entries = await _library.getAll();
      final overrides = await _metadata.getAll();
      final overrideByPath = <String, LocalMediaMetadata>{
        for (final item in overrides) _pathKey(item.sourcePath): item,
      };
      final songs = entries
          .map(
            (entry) => _CatalogSong(
              entry: entry,
              override: overrideByPath[_pathKey(entry.sourcePath)],
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ArtistGroup> get _artists {
    final grouped = <String, List<_CatalogSong>>{};
    for (final song in _songs) {
      grouped.putIfAbsent(song.artistDisplay, () => <_CatalogSong>[]).add(song);
    }
    final result =
        grouped.entries
            .map((entry) => _ArtistGroup(name: entry.key, songs: entry.value))
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return result;
  }

  List<_AlbumGroup> get _albums => _albumsFor(_songs);

  List<_AlbumGroup> _albumsFor(List<_CatalogSong> songs) {
    final grouped = <String, List<_CatalogSong>>{};
    for (final song in songs) {
      grouped.putIfAbsent(song.albumKey, () => <_CatalogSong>[]).add(song);
    }
    final result =
        grouped.entries
            .map((entry) {
              final first = entry.value.first;
              return _AlbumGroup(
                key: entry.key,
                title: first.albumDisplay,
                artist: first.artistDisplay,
                songs: entry.value,
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final byArtist = a.artist.toLowerCase().compareTo(
              b.artist.toLowerCase(),
            );
            if (byArtist != 0) return byArtist;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    return result;
  }

  _ArtistGroup? _artistByName(String name) {
    for (final artist in _artists) {
      if (artist.name == name) return artist;
    }
    return null;
  }

  _AlbumGroup? _albumByKey(String key) {
    for (final album in _albums) {
      if (album.key == key) return album;
    }
    return null;
  }

  Future<void> _playSongs(
    List<_CatalogSong> songs, {
    int requestedIndex = 0,
  }) async {
    final playable = <PlaybackItem>[];
    var playableBeforeRequested = 0;
    for (var i = 0; i < songs.length; i++) {
      final item = songs[i].playbackItem;
      if (item == null) continue;
      if (i < requestedIndex) playableBeforeRequested += 1;
      playable.add(item);
    }
    if (playable.isEmpty) return;
    final startIndex = playableBeforeRequested
        .clamp(0, playable.length - 1)
        .toInt();
    await _session.setQueue(playable, startIndex: startIndex);
  }

  Future<void> _enqueue(_CatalogSong song) async {
    final item = song.playbackItem;
    if (item != null) await _session.enqueue(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: Text(widget.view == LocalCatalogView.artists ? '艺人' : '专辑'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: _loading
          ? const AppLoadingState()
          : _error != null
          ? _CatalogError(message: _error!, onRetry: _reload)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_songs.isEmpty) {
      return const _CatalogEmpty(
        title: '音乐库还没有歌曲',
        message: '先在“歌曲”中添加本地音乐，艺人和专辑会自动从标签中建立。',
      );
    }

    final albumKey = _selectedAlbumKey;
    if (albumKey != null) {
      final album = _albumByKey(albumKey);
      if (album != null) return _buildAlbumDetail(album);
    }

    if (widget.view == LocalCatalogView.artists) {
      final artistName = _selectedArtist;
      if (artistName != null) {
        final artist = _artistByName(artistName);
        if (artist != null) return _buildArtistDetail(artist);
      }
      return _buildArtistGrid();
    }

    return _buildAlbumGrid(_albums);
  }

  Widget _buildArtistGrid() {
    final artists = _artists;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: AppCatalogCard.gridDelegateFor(layout),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            final subtitle =
                '${artist.songs.length} 首 · ${artist.albumCount} 张专辑';
            return AppCatalogCard(
              artwork: AppArtwork.person(path: artist.artworkPath),
              title: artist.name,
              subtitle: subtitle,
              semanticLabel: LocalLibrarySemantics.catalogCard(
                title: artist.name,
                detail: subtitle,
              ),
              semanticHint: LocalLibrarySemantics.openArtistHint,
              compact: layout.isCompact,
              onTap: () => setState(() => _selectedArtist = artist.name),
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumGrid(List<_AlbumGroup> albums) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: AppCatalogCard.gridDelegateFor(layout),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final subtitle = '${album.artist} · ${album.songs.length} 首';
            return AppCatalogCard(
              artwork: AppArtwork(
                path: album.artworkPath,
                borderRadius: AppArtwork.tileRadius,
              ),
              title: album.title,
              subtitle: subtitle,
              semanticLabel: LocalLibrarySemantics.catalogCard(
                title: album.title,
                detail: subtitle,
              ),
              semanticHint: LocalLibrarySemantics.openAlbumHint,
              compact: layout.isCompact,
              onTap: () => setState(() => _selectedAlbumKey = album.key),
            );
          },
        );
      },
    );
  }

  Widget _buildArtistDetail(_ArtistGroup artist) {
    final layout = AppResponsive.of(context);
    final albums = _albumsFor(artist.songs);
    final songs = List<_CatalogSong>.from(artist.songs)
      ..sort((a, b) {
        final byAlbum = a.albumDisplay.compareTo(b.albumDisplay);
        if (byAlbum != 0) return byAlbum;
        final aTrack = a.entry.embeddedTrackNumber ?? 1 << 20;
        final bTrack = b.entry.embeddedTrackNumber ?? 1 << 20;
        final byTrack = aTrack.compareTo(bTrack);
        if (byTrack != 0) return byTrack;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final playable = songs.where((song) => song.playbackItem != null).length;
    final miniWidth = layout.isCompact
        ? 132.0
        : layout.isMedium
        ? 148.0
        : 160.0;
    final shelfHeight = miniWidth + 58;

    return Column(
      children: [
        _CatalogHero(
          artworkPath: artist.artworkPath,
          roundArtwork: true,
          title: artist.name,
          subtitle: '${songs.length} 首歌曲 · ${albums.length} 张专辑',
          onBack: () => setState(() => _selectedArtist = null),
          onPlay: playable == 0 ? null : () => _playSongs(songs),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              layout.pageGutter,
              0,
              layout.pageGutter,
              layout.pageGutter,
            ),
            children: [
              if (albums.isNotEmpty) ...[
                const _SectionTitle('专辑'),
                SizedBox(
                  height: shelfHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: albums.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return SizedBox(
                        width: miniWidth,
                        child: _MiniAlbumCard(
                          album: album,
                          artworkSize: miniWidth - 10,
                          onTap: () =>
                              setState(() => _selectedAlbumKey = album.key),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: layout.sectionGap),
              ],
              const _SectionTitle('全部歌曲'),
              ...List.generate(
                songs.length,
                (index) => _CatalogSongTile(
                  song: songs[index],
                  index: index,
                  dependencies: widget.dependencies,
                  onPlay: () => _playSongs(songs, requestedIndex: index),
                  onEnqueue: () => _enqueue(songs[index]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumDetail(_AlbumGroup album) {
    final layout = AppResponsive.of(context);
    final songs = List<_CatalogSong>.from(album.songs)
      ..sort((a, b) {
        final aTrack = a.entry.embeddedTrackNumber ?? 1 << 20;
        final bTrack = b.entry.embeddedTrackNumber ?? 1 << 20;
        final byTrack = aTrack.compareTo(bTrack);
        if (byTrack != 0) return byTrack;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final playable = songs.where((song) => song.playbackItem != null).length;
    final years =
        songs
            .map((song) => song.entry.embeddedYear)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    final yearText = years.isEmpty ? '' : ' · ${years.first}';

    return Column(
      children: [
        _CatalogHero(
          artworkPath: album.artworkPath,
          title: album.title,
          subtitle: '${album.artist}$yearText · ${songs.length} 首歌曲',
          onBack: () => setState(() => _selectedAlbumKey = null),
          onPlay: playable == 0 ? null : () => _playSongs(songs),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              layout.pageGutter,
              AppSpacing.sm,
              layout.pageGutter,
              layout.pageGutter,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) => _CatalogSongTile(
              song: songs[index],
              index: index,
              dependencies: widget.dependencies,
              onPlay: () => _playSongs(songs, requestedIndex: index),
              onEnqueue: () => _enqueue(songs[index]),
              showTrackNumber: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogSong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;

  const _CatalogSong({required this.entry, required this.override});

  String get fileName => entry.sourcePath.split(Platform.pathSeparator).last;
  String get fallbackTitle => fileName.replaceAll(
    RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
    '',
  );
  String get embeddedTitle => entry.embeddedTitle?.trim().isNotEmpty == true
      ? entry.embeddedTitle!
      : fallbackTitle;
  String get title => override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;

  String get artistDisplay {
    final value =
        override?.resolvedArtist(entry.embeddedArtist) ?? entry.embeddedArtist;
    return value?.trim().isNotEmpty == true ? value!.trim() : '未知艺人';
  }

  String get albumDisplay {
    final value =
        override?.resolvedAlbum(entry.embeddedAlbum) ?? entry.embeddedAlbum;
    return value?.trim().isNotEmpty == true ? value!.trim() : '未知专辑';
  }

  String get albumKey => '$artistDisplay\u0000$albumDisplay';
  String? get artworkPath =>
      override?.resolvedArtwork(entry.embeddedArtworkPath) ??
      entry.embeddedArtworkPath;
  bool get hasLyrics => override?.metadata['linkedProjectId'] is String;

  PlaybackItem? get playbackItem {
    if (entry.isMissing || !File(entry.sourcePath).existsSync()) return null;
    return PlaybackItem(
      id: 'local:${entry.sourcePath}',
      title: title,
      artist: artistDisplay == '未知艺人' ? null : artistDisplay,
      artworkPath: artworkPath,
      hasLyrics: hasLyrics,
      audioAsset: AudioAsset(
        originalPath: entry.sourcePath,
        format: entry.format,
        thumbnailPath: artworkPath,
      ),
      preferredSource: AudioSourceType.original,
    );
  }
}

class _ArtistGroup {
  final String name;
  final List<_CatalogSong> songs;

  const _ArtistGroup({required this.name, required this.songs});

  int get albumCount => songs.map((song) => song.albumDisplay).toSet().length;

  String? get artworkPath {
    for (final song in songs) {
      final path = song.artworkPath;
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }
}

class _AlbumGroup {
  final String key;
  final String title;
  final String artist;
  final List<_CatalogSong> songs;

  const _AlbumGroup({
    required this.key,
    required this.title,
    required this.artist,
    required this.songs,
  });

  String? get artworkPath {
    for (final song in songs) {
      final path = song.artworkPath;
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }
}

class _CatalogHero extends StatelessWidget {
  final String? artworkPath;
  final String title;
  final String subtitle;
  final bool roundArtwork;
  final VoidCallback onBack;
  final VoidCallback? onPlay;

  const _CatalogHero({
    required this.artworkPath,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onPlay,
    this.roundArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final compact = layout.isCompactOrMedium || layout.isShort;
        final artworkSize = layout.isShort
            ? 96.0
            : layout.isCompact
            ? 112.0
            : layout.isMedium
            ? 128.0
            : 150.0;
        final artwork = roundArtwork
            ? AppArtwork.person(path: artworkPath, size: artworkSize)
            : AppArtwork(
                path: artworkPath,
                size: artworkSize,
                borderRadius: AppArtwork.tileRadius,
              );
        final info = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style:
                  (layout.isCompact
                          ? Theme.of(context).textTheme.headlineSmall
                          : Theme.of(context).textTheme.headlineMedium)
                      ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  layout.minimumInteractiveExtent,
                  layout.minimumInteractiveExtent,
                ),
              ),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放'),
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.all(layout.pageGutter),
          child: compact
              ? Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: '返回',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    artwork,
                    const SizedBox(height: AppSpacing.md),
                    info,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    artwork,
                    SizedBox(width: layout.sectionGap),
                    Expanded(child: info),
                  ],
                ),
        );
      },
    );
  }
}

class _CatalogSongTile extends StatelessWidget {
  final _CatalogSong song;
  final int index;
  final LocalLibraryDependencies dependencies;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final bool showTrackNumber;

  const _CatalogSongTile({
    required this.song,
    required this.index,
    required this.dependencies,
    required this.onPlay,
    required this.onEnqueue,
    this.showTrackNumber = false,
  });

  void _addToPlaylist(BuildContext context) {
    showAddToLocalPlaylistDialog(
      context,
      sourcePath: song.entry.sourcePath,
      title: song.title,
      repository: dependencies.collectionRepository,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = song.playbackItem;
    final layout = AppResponsive.of(context);
    final compact = layout.isCompact;
    final available = item != null;
    final collectionRepository = dependencies.collectionRepository;

    final favorite = LocalFavoriteButton(
      sourcePath: song.entry.sourcePath,
      repository: collectionRepository,
      iconSize: 20,
    );
    final trailing = compact
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              favorite,
              PopupMenuButton<String>(
                tooltip: '更多歌曲操作',
                enabled: available,
                onSelected: (value) {
                  if (value == 'playlist') _addToPlaylist(context);
                  if (value == 'queue') onEnqueue();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'playlist', child: Text('加入播放列表')),
                  PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              favorite,
              IconButton(
                tooltip: '加入播放列表',
                onPressed: available ? () => _addToPlaylist(context) : null,
                icon: const Icon(Icons.playlist_add_rounded),
              ),
              IconButton(
                tooltip: '加入播放队列',
                onPressed: available ? onEnqueue : null,
                icon: const Icon(Icons.queue_music_rounded),
              ),
            ],
          );

    return NowPlayingListener(
      playbackSession: dependencies.playbackSession,
      audioPlayer: dependencies.audioPlayer,
      builder: (context, nowPlaying) => AppSongRow(
        title: song.title,
        subtitle: showTrackNumber
            ? song.artistDisplay
            : '${song.artistDisplay} · ${song.albumDisplay}',
        unavailable: !available,
        index: showTrackNumber
            ? song.entry.embeddedTrackNumber?.toString() ?? '${index + 1}'
            : null,
        artwork: showTrackNumber
            ? null
            : available
            ? AppArtwork(
                path: song.artworkPath,
                borderRadius: AppArtwork.rowRadius,
              )
            : AppArtwork.missing(
                path: song.artworkPath,
                borderRadius: AppArtwork.rowRadius,
              ),
        playback: available
            ? nowPlaying.playbackForPath(song.entry.sourcePath)
            : AppSongRowPlayback.none,
        onTap: onPlay,
        semanticActions: {
          if (available) '加入播放列表': () => _addToPlaylist(context),
          if (available) '加入播放队列': onEnqueue,
        },
        trailing: trailing,
      ),
    );
  }
}

class _MiniAlbumCard extends StatelessWidget {
  final _AlbumGroup album;
  final double artworkSize;
  final VoidCallback onTap;

  const _MiniAlbumCard({
    required this.album,
    required this.artworkSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppTapTarget(
      label: LocalLibrarySemantics.miniAlbum(
        title: album.title,
        songs: album.songs.length,
      ),
      hint: LocalLibrarySemantics.openAlbumHint,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppArtwork(
              path: album.artworkPath,
              size: artworkSize,
              borderRadius: AppArtwork.tileRadius,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${album.songs.length} 首',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CatalogEmpty extends StatelessWidget {
  final String title;
  final String message;

  const _CatalogEmpty({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.library_music_rounded,
      title: title,
      message: message,
    );
  }
}

class _CatalogError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CatalogError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(title: '媒体分类加载失败', message: message, onRetry: onRetry);
  }
}
