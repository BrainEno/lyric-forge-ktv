import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_media_metadata_dialog.dart';
import '../widgets/local_song_lyrics_import_action.dart';

class LocalMediaLibraryScreenV2 extends StatefulWidget {
  const LocalMediaLibraryScreenV2({super.key});

  @override
  State<LocalMediaLibraryScreenV2> createState() =>
      _LocalMediaLibraryScreenV2State();
}

class _LocalMediaLibraryScreenV2State
    extends State<LocalMediaLibraryScreenV2> {
  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _overrides;
  late final AudioLibraryImportService _importer;
  late final PlaybackSessionService _session;
  late final TextEditingController _searchController;

  List<_ResolvedLibrarySong> _songs = const [];
  bool _loading = true;
  bool _working = false;
  bool _grid = true;
  String _query = '';
  String _artist = '';
  String _album = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _overrides = services.localMediaMetadataRepository;
    _importer = services.audioLibraryImportService;
    _session = services.playbackSessionService;
    _searchController = TextEditingController();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _pathKey(String path) {
    final value = File(path).absolute.path;
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  Future<void> _reload({bool rescan = false, bool forceTags = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      if (rescan) {
        await _library.refreshFromRoots(_importer.supportedExtensions);
      }
      if (forceTags) {
        await _library.refreshMetadata(force: true);
      }
      final entries = await _library.getAll();
      final overrides = await _overrides.getAll();
      final overrideByPath = <String, LocalMediaMetadata>{
        for (final item in overrides) _pathKey(item.sourcePath): item,
      };
      final songs = entries
          .map(
            (entry) => _ResolvedLibrarySong(
              entry: entry,
              override: overrideByPath[_pathKey(entry.sourcePath)],
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _songs = songs;
        if (_artist.isNotEmpty && !_artists.contains(_artist)) _artist = '';
        if (_album.isNotEmpty && !_albums.contains(_album)) _album = '';
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '音乐库加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _artists {
    final values = _songs
        .map((song) => song.artist)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _albums {
    final values = _songs
        .map((song) => song.album)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<_ResolvedLibrarySong> get _visibleSongs {
    final query = _query.trim().toLowerCase();
    return _songs.where((song) {
      if (_artist.isNotEmpty && song.artist != _artist) return false;
      if (_album.isNotEmpty && song.album != _album) return false;
      if (query.isEmpty) return true;
      return song.searchText.contains(query);
    }).toList(growable: false);
  }

  Future<void> _addFiles() async {
    await _withWork(() async {
      final paths = await _importer.pickAudioFiles();
      if (paths.isNotEmpty) await _reload();
    });
  }

  Future<void> _addFolder() async {
    await _withWork(() async {
      final paths = await _importer.pickAudioDirectory();
      if (paths.isNotEmpty) await _reload();
    });
  }

  Future<void> _withWork(Future<void> Function() work) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _play(_ResolvedLibrarySong song) async {
    if (song.entry.isMissing) return;
    final queue = _visibleSongs.where((item) => !item.entry.isMissing).toList();
    final index = queue.indexWhere(
      (item) => _pathKey(item.entry.sourcePath) == _pathKey(song.entry.sourcePath),
    );
    if (index < 0) return;
    await _session.setQueue(
      queue.map((item) => item.playbackItem).toList(growable: false),
      startIndex: index,
    );
  }

  Future<void> _enqueue(_ResolvedLibrarySong song) async {
    if (song.entry.isMissing) return;
    await _session.enqueue(song.playbackItem);
  }

  Future<void> _edit(_ResolvedLibrarySong song) async {
    if (song.entry.isMissing) return;
    await showLocalMediaMetadataDialog(context, song.playbackItem);
    await _reload();
  }

  Future<void> _lyrics(_ResolvedLibrarySong song) async {
    if (song.entry.isMissing) return;
    await importLyricsForLocalPlaybackItem(context, song.playbackItem);
    await _reload();
  }

  Future<void> _remove(_ResolvedLibrarySong song) async {
    await _library.remove(song.entry.sourcePath);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final songs = _visibleSongs;
    final missing = _songs.where((song) => song.entry.isMissing).length;
    final tagged = _songs.where((song) => song.entry.hasEmbeddedPresentationMetadata).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text('音乐库'),
        actions: [
          IconButton(
            tooltip: '刷新音乐文件夹',
            onPressed: _working ? null : () => _withWork(() => _reload(rescan: true)),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '重新读取音频标签',
            onPressed: _working
                ? null
                : () => _withWork(() => _reload(forceTags: true)),
            icon: const Icon(Icons.manage_search_rounded),
          ),
          IconButton(
            tooltip: '添加音乐文件',
            onPressed: _working ? null : _addFiles,
            icon: const Icon(Icons.library_add_rounded),
          ),
          IconButton(
            tooltip: '添加音乐文件夹',
            onPressed: _working ? null : _addFolder,
            icon: const Icon(Icons.create_new_folder_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _LibraryHeader(
              controller: _searchController,
              total: _songs.length,
              visible: songs.length,
              tagged: tagged,
              missing: missing,
              artists: _artists,
              albums: _albums,
              artist: _artist,
              album: _album,
              grid: _grid,
              onQuery: (value) => setState(() => _query = value),
              onClearQuery: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              onArtist: (value) => setState(() => _artist = value),
              onAlbum: (value) => setState(() => _album = value),
              onGrid: (value) => setState(() => _grid = value),
              onCleanMissing: missing == 0
                  ? null
                  : () => _withWork(() async {
                        await _library.removeMissing();
                        await _reload();
                      }),
            ),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(_error!, style: const TextStyle(color: AppColors.error)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _songs.isEmpty
                      ? _EmptyLibrary(onFiles: _addFiles, onFolder: _addFolder)
                      : songs.isEmpty
                          ? const Center(child: Text('没有符合当前条件的歌曲'))
                          : _grid
                              ? _SongGrid(
                                  songs: songs,
                                  onPlay: _play,
                                  onEnqueue: _enqueue,
                                  onEdit: _edit,
                                  onLyrics: _lyrics,
                                  onRemove: _remove,
                                )
                              : _SongList(
                                  songs: songs,
                                  onPlay: _play,
                                  onEnqueue: _enqueue,
                                  onEdit: _edit,
                                  onLyrics: _lyrics,
                                  onRemove: _remove,
                                ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedLibrarySong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;

  const _ResolvedLibrarySong({required this.entry, required this.override});

  String get fileName => entry.sourcePath.split(Platform.pathSeparator).last;
  String get fallbackTitle => fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
        '',
      );
  String get embeddedTitle =>
      entry.embeddedTitle?.trim().isNotEmpty == true ? entry.embeddedTitle! : fallbackTitle;
  String get title => override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;
  String? get artist => override?.resolvedArtist(entry.embeddedArtist) ?? entry.embeddedArtist;
  String? get album => override?.resolvedAlbum(entry.embeddedAlbum) ?? entry.embeddedAlbum;
  String? get artworkPath =>
      override?.resolvedArtwork(entry.embeddedArtworkPath) ?? entry.embeddedArtworkPath;
  bool get hasLyrics => override?.metadata['linkedProjectId'] is String;
  bool get hasUserOverride => override?.hasOverrides == true;

  String get searchText => [
        title,
        artist ?? '',
        album ?? '',
        entry.embeddedGenres.join(' '),
        fileName,
        entry.sourcePath,
      ].join('\n').toLowerCase();

  String get secondary => [
        if (artist?.trim().isNotEmpty == true) artist!,
        if (album?.trim().isNotEmpty == true) album!,
        entry.format.toUpperCase(),
      ].join(' · ');

  PlaybackItem get playbackItem => PlaybackItem(
        id: 'local:${entry.sourcePath}',
        title: title,
        artist: artist,
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

class _LibraryHeader extends StatelessWidget {
  final TextEditingController controller;
  final int total;
  final int visible;
  final int tagged;
  final int missing;
  final List<String> artists;
  final List<String> albums;
  final String artist;
  final String album;
  final bool grid;
  final ValueChanged<String> onQuery;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onArtist;
  final ValueChanged<String> onAlbum;
  final ValueChanged<bool> onGrid;
  final VoidCallback? onCleanMissing;

  const _LibraryHeader({
    required this.controller,
    required this.total,
    required this.visible,
    required this.tagged,
    required this.missing,
    required this.artists,
    required this.albums,
    required this.artist,
    required this.album,
    required this.grid,
    required this.onQuery,
    required this.onClearQuery,
    required this.onArtist,
    required this.onAlbum,
    required this.onGrid,
    required this.onCleanMissing,
  });

  @override
  Widget build(BuildContext context) {
    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Filter(value: artist, allLabel: '全部艺人', values: artists, onChanged: onArtist),
        _Filter(value: album, allLabel: '全部专辑', values: albums, onChanged: onAlbum),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded)),
            ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded)),
          ],
          selected: {grid},
          showSelectedIcon: false,
          onSelectionChanged: (value) => onGrid(value.first),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: controller,
                onChanged: onQuery,
                decoration: InputDecoration(
                  hintText: '搜索歌曲、艺人、专辑、流派或文件名',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(onPressed: onClearQuery, icon: const Icon(Icons.close_rounded)),
                ),
              );
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [search, const SizedBox(height: AppSpacing.sm), Align(alignment: Alignment.centerLeft, child: controls)],
                );
              }
              return Row(children: [Expanded(child: search), const SizedBox(width: AppSpacing.md), controls]);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(visible == total ? '$total 首歌曲' : '$visible / $total 首'),
              Text('$tagged 首已读取内嵌标签', style: const TextStyle(color: AppColors.textTertiary)),
              if (missing > 0) Text('$missing 个文件不可用', style: const TextStyle(color: AppColors.error)),
              if (missing > 0) TextButton(onPressed: onCleanMissing, child: const Text('清理缺失项')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  final String value;
  final String allLabel;
  final List<String> values;
  final ValueChanged<String> onChanged;

  const _Filter({required this.value, required this.allLabel, required this.values, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      items: [
        DropdownMenuItem(value: '', child: Text(allLabel)),
        ...values.map((item) => DropdownMenuItem(value: item, child: Text(item))),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _SongGrid extends StatelessWidget {
  final List<_ResolvedLibrarySong> songs;
  final ValueChanged<_ResolvedLibrarySong> onPlay;
  final ValueChanged<_ResolvedLibrarySong> onEnqueue;
  final ValueChanged<_ResolvedLibrarySong> onEdit;
  final ValueChanged<_ResolvedLibrarySong> onLyrics;
  final ValueChanged<_ResolvedLibrarySong> onRemove;

  const _SongGrid({required this.songs, required this.onPlay, required this.onEnqueue, required this.onEdit, required this.onLyrics, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1400 ? 6 : constraints.maxWidth >= 1100 ? 5 : constraints.maxWidth >= 820 ? 4 : constraints.maxWidth >= 560 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.72,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) => _SongCard(
            song: songs[index],
            onPlay: () => onPlay(songs[index]),
            onEnqueue: () => onEnqueue(songs[index]),
            onEdit: () => onEdit(songs[index]),
            onLyrics: () => onLyrics(songs[index]),
            onRemove: () => onRemove(songs[index]),
          ),
        );
      },
    );
  }
}

class _SongList extends StatelessWidget {
  final List<_ResolvedLibrarySong> songs;
  final ValueChanged<_ResolvedLibrarySong> onPlay;
  final ValueChanged<_ResolvedLibrarySong> onEnqueue;
  final ValueChanged<_ResolvedLibrarySong> onEdit;
  final ValueChanged<_ResolvedLibrarySong> onLyrics;
  final ValueChanged<_ResolvedLibrarySong> onRemove;

  const _SongList({required this.songs, required this.onPlay, required this.onEnqueue, required this.onEdit, required this.onLyrics, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: songs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          enabled: !song.entry.isMissing,
          leading: SizedBox(width: 52, height: 52, child: _Artwork(song)),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(song.entry.isMissing ? '文件不可用' : song.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: song.entry.isMissing ? null : () => onPlay(song),
          trailing: _SongMenu(song: song, onEnqueue: () => onEnqueue(song), onEdit: () => onEdit(song), onLyrics: () => onLyrics(song), onRemove: () => onRemove(song)),
        );
      },
    );
  }
}

class _SongCard extends StatelessWidget {
  final _ResolvedLibrarySong song;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback onRemove;

  const _SongCard({required this.song, required this.onPlay, required this.onEnqueue, required this.onEdit, required this.onLyrics, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: song.entry.isMissing ? null : onPlay,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: song.entry.isMissing ? AppColors.error.withAlpha(80) : AppColors.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Artwork(song)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                _SongMenu(song: song, onEnqueue: onEnqueue, onEdit: onEdit, onLyrics: onLyrics, onRemove: onRemove),
              ],
            ),
            Text(song.entry.isMissing ? '文件不可用' : (song.artist ?? '本地音乐'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(
              [if (song.entry.embeddedTrackNumber != null) '#${song.entry.embeddedTrackNumber}', song.entry.format.toUpperCase(), if (song.hasUserOverride) '已编辑', if (song.hasLyrics) '有歌词'].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongMenu extends StatelessWidget {
  final _ResolvedLibrarySong song;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback onRemove;

  const _SongMenu({required this.song, required this.onEnqueue, required this.onEdit, required this.onLyrics, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'queue') onEnqueue();
        if (value == 'edit') onEdit();
        if (value == 'lyrics') onLyrics();
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => [
        if (!song.entry.isMissing) const PopupMenuItem(value: 'queue', child: Text('加入播放队列')),
        if (!song.entry.isMissing) const PopupMenuItem(value: 'edit', child: Text('编辑资料与封面')),
        if (!song.entry.isMissing) PopupMenuItem(value: 'lyrics', child: Text(song.hasLyrics ? '打开歌词' : '导入歌词')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('从音乐库移除')),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _Artwork extends StatelessWidget {
  final _ResolvedLibrarySong song;

  const _Artwork(this.song);

  @override
  Widget build(BuildContext context) {
    final file = song.artworkPath == null ? null : File(song.artworkPath!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: file?.existsSync() == true
          ? Image.file(file!, fit: BoxFit.cover)
          : Container(
              color: AppColors.bgSurface,
              alignment: Alignment.center,
              child: Icon(song.entry.isMissing ? Icons.link_off_rounded : Icons.album_rounded, color: song.entry.isMissing ? AppColors.error : AppColors.textTertiary, size: 50),
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onFiles;
  final VoidCallback onFolder;

  const _EmptyLibrary({required this.onFiles, required this.onFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music_rounded, size: 72, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text('建立你的本地音乐库', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          const Text('导入后会自动读取原音频的标题、艺人、专辑和内嵌封面。'),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilledButton.icon(onPressed: onFolder, icon: const Icon(Icons.folder_rounded), label: const Text('添加音乐文件夹')),
              OutlinedButton.icon(onPressed: onFiles, icon: const Icon(Icons.audio_file_rounded), label: const Text('添加音乐文件')),
            ],
          ),
        ],
      ),
    );
  }
}
