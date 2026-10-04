import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_collection_actions.dart';

enum LocalCatalogView { artists, albums }

class LocalArtistAlbumBrowserScreen extends StatefulWidget {
  final LocalCatalogView view;

  const LocalArtistAlbumBrowserScreen({
    super.key,
    required this.view,
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
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _metadata = services.localMediaMetadataRepository;
    _session = services.playbackSessionService;
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
      if (mounted) setState(() => _error = '媒体分类加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ArtistGroup> get _artists {
    final grouped = <String, List<_CatalogSong>>{};
    for (final song in _songs) {
      grouped.putIfAbsent(song.artistDisplay, () => <_CatalogSong>[]).add(song);
    }
    final result = grouped.entries
        .map((entry) => _ArtistGroup(name: entry.key, songs: entry.value))
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  List<_AlbumGroup> get _albums => _albumsFor(_songs);

  List<_AlbumGroup> _albumsFor(List<_CatalogSong> songs) {
    final grouped = <String, List<_CatalogSong>>{};
    for (final song in songs) {
      grouped.putIfAbsent(song.albumKey, () => <_CatalogSong>[]).add(song);
    }
    final result = grouped.entries.map((entry) {
      final first = entry.value.first;
      return _AlbumGroup(
        key: entry.key,
        title: first.albumDisplay,
        artist: first.artistDisplay,
        songs: entry.value,
      );
    }).toList(growable: false)
      ..sort((a, b) {
        final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
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
          ? const Center(child: CircularProgressIndicator())
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
        final columns = layout.gridColumns(
          minTileWidth: layout.isCompact ? 160 : 190,
          min: layout.isCompact ? 2 : 2,
          max: 7,
        );
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: layout.isCompact ? 0.78 : 0.76,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return _CatalogCard(
              artworkPath: artist.artworkPath,
              title: artist.name,
              subtitle: '${artist.songs.length} 首 · ${artist.albumCount} 张专辑',
              roundArtwork: true,
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
        final columns = layout.gridColumns(
          minTileWidth: layout.isCompact ? 160 : 190,
          min: layout.isCompact ? 2 : 2,
          max: 7,
        );
        return GridView.builder(
          padding: EdgeInsets.all(layout.pageGutter),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: layout.isCompact ? 0.73 : 0.72,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _CatalogCard(
              artworkPath: album.artworkPath,
              title: album.title,
              subtitle: '${album.artist} · ${album.songs.length} 首',
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
                    separatorBuilder: (_, __) =>
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
    final years = songs
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
        final artwork = _CatalogArtwork(
          path: artworkPath,
          size: artworkSize,
          round: roundArtwork,
        );
        final info = Column(
          crossAxisAlignment:
              compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: (layout.isCompact
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
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final bool showTrackNumber;

  const _CatalogSongTile({
    required this.song,
    required this.index,
    required this.onPlay,
    required this.onEnqueue,
    this.showTrackNumber = false,
  });

  @override
  Widget build(BuildContext context) {
    final item = song.playbackItem;
    final layout = AppResponsive.of(context);
    final compact = layout.isCompact;

    final queueAction = IconButton(
      tooltip: '加入播放队列',
      onPressed: item == null ? null : onEnqueue,
      icon: const Icon(Icons.queue_music_rounded),
    );
    final playlistAction = IconButton(
      tooltip: '加入播放列表',
      onPressed: item == null
          ? null
          : () => showAddToLocalPlaylistDialog(
                context,
                sourcePath: song.entry.sourcePath,
                title: song.title,
              ),
      icon: const Icon(Icons.playlist_add_rounded),
    );

    return ListTile(
      enabled: item != null,
      minVerticalPadding: compact ? AppSpacing.sm : null,
      leading: SizedBox(
        width: layout.minimumInteractiveExtent,
        height: layout.minimumInteractiveExtent,
        child: showTrackNumber
            ? Center(
                child: Text(
                  song.entry.embeddedTrackNumber?.toString() ?? '${index + 1}',
                ),
              )
            : _CatalogArtwork(
                path: song.artworkPath,
                size: layout.minimumInteractiveExtent,
              ),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item == null
            ? '文件不可用'
            : '${song.artistDisplay} · ${song.albumDisplay}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: item == null ? null : onPlay,
      trailing: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LocalFavoriteButton(
                  sourcePath: song.entry.sourcePath,
                  iconSize: 20,
                ),
                PopupMenuButton<String>(
                  tooltip: '更多歌曲操作',
                  onSelected: (value) {
                    if (value == 'playlist' && item != null) {
                      showAddToLocalPlaylistDialog(
                        context,
                        sourcePath: song.entry.sourcePath,
                        title: song.title,
                      );
                    }
                    if (value == 'queue' && item != null) onEnqueue();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'playlist',
                      child: Text('加入播放列表'),
                    ),
                    PopupMenuItem(
                      value: 'queue',
                      child: Text('加入播放队列'),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            )
          : Wrap(
              spacing: AppSpacing.xs,
              children: [
                LocalFavoriteButton(
                  sourcePath: song.entry.sourcePath,
                  iconSize: 20,
                ),
                playlistAction,
                queueAction,
              ],
            ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  final String? artworkPath;
  final String title;
  final String subtitle;
  final bool roundArtwork;
  final bool compact;
  final VoidCallback onTap;

  const _CatalogCard({
    required this.artworkPath,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.roundArtwork = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest.shortestSide;
                  return Center(
                    child: _CatalogArtwork(
                      path: artworkPath,
                      size: size,
                      round: roundArtwork,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textTertiary),
            ),
          ],
        ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CatalogArtwork(path: album.artworkPath, size: artworkSize),
          const SizedBox(height: AppSpacing.xs),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            '${album.songs.length} 首',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CatalogArtwork extends StatelessWidget {
  final String? path;
  final double size;
  final bool round;

  const _CatalogArtwork({
    required this.path,
    required this.size,
    this.round = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final child = file?.existsSync() == true
        ? Image.file(file!, width: size, height: size, fit: BoxFit.cover)
        : Container(
            width: size,
            height: size,
            color: AppColors.bgSurface,
            alignment: Alignment.center,
            child: Icon(
              round ? Icons.person_rounded : Icons.album_rounded,
              size: size * 0.36,
              color: AppColors.textTertiary,
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(round ? size / 2 : 12),
      child: child,
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
        style: Theme.of(context)
            .textTheme
            .titleLarge
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
    final layout = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_rounded, size: 64),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CatalogError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 52,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
