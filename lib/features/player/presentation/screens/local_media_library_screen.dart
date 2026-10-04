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

class LocalMediaLibraryScreen extends StatefulWidget {
  const LocalMediaLibraryScreen({super.key});

  @override
  State<LocalMediaLibraryScreen> createState() => _LocalMediaLibraryScreenState();
}

class _LocalMediaLibraryScreenState extends State<LocalMediaLibraryScreen> {
  late final LocalMediaLibraryRepository _library;
  late final LocalMediaMetadataRepository _metadata;
  late final AudioLibraryImportService _importer;
  late final PlaybackSessionService _session;
  late final TextEditingController _searchController;

  List<_LibrarySong> _songs = const [];
  bool _loading = true;
  bool _working = false;
  bool _grid = true;
  String _query = '';
  String _artistFilter = '';
  String _albumFilter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _metadata = services.localMediaMetadataRepository;
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

  Future<void> _reload({bool refreshAvailability = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final entries = refreshAvailability
          ? await _library.refreshAvailability()
          : await _library.getAll();
      final overrides = await _metadata.getAll();
      final byPath = <String, LocalMediaMetadata>{
        for (final value in overrides) _pathKey(value.sourcePath): value,
      };
      final songs = entries
          .map(
            (entry) => _LibrarySong(
              entry: entry,
              metadata: byPath[_pathKey(entry.sourcePath)],
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _error = null;
        if (_artistFilter.isNotEmpty && !_artists.contains(_artistFilter)) {
          _artistFilter = '';
        }
        if (_albumFilter.isNotEmpty && !_albums.contains(_albumFilter)) {
          _albumFilter = '';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '音乐库加载失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  List<String> get _artists {
    final result = _songs
        .map((song) => song.artist)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<String> get _albums {
    final result = _songs
        .map((song) => song.album)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<_LibrarySong> get _visibleSongs {
    final query = _query.trim().toLowerCase();
    return _songs.where((song) {
      if (_artistFilter.isNotEmpty && song.artist != _artistFilter) return false;
      if (_albumFilter.isNotEmpty && song.album != _albumFilter) return false;
      if (query.isEmpty) return true;
      return song.searchText.contains(query);
    }).toList(growable: false);
  }

  Future<void> _addFiles() => _runImport(_importer.pickAudioFiles);

  Future<void> _addFolder() => _runImport(_importer.pickAudioDirectory);

  Future<void> _runImport(Future<List<String>> Function() picker) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final paths = await picker();
      if (paths.isEmpty) return;
      await _library.addPaths(paths);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入音乐库：${paths.length} 个音频文件')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '导入音乐失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshFiles() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await _reload(refreshAvailability: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _play(_LibrarySong song) async {
    if (song.entry.isMissing) return;
    final playable = _visibleSongs.where((value) => !value.entry.isMissing).toList();
    final index = playable.indexWhere(
      (value) => _pathKey(value.entry.sourcePath) == _pathKey(song.entry.sourcePath),
    );
    if (index < 0) return;
    await _session.setQueue(
      playable.map((value) => value.playbackItem).toList(growable: false),
      startIndex: index,
    );
  }

  Future<void> _enqueue(_LibrarySong song) async {
    if (song.entry.isMissing) return;
    await _session.enqueue(song.playbackItem);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入队列：${song.title}')),
      );
    }
  }

  Future<void> _edit(_LibrarySong song) async {
    if (song.entry.isMissing) return;
    await showLocalMediaMetadataDialog(context, song.playbackItem);
    await _reload();
  }

  Future<void> _lyrics(_LibrarySong song) async {
    if (song.entry.isMissing) return;
    await importLyricsForLocalPlaybackItem(context, song.playbackItem);
    await _reload();
  }

  Future<void> _remove(_LibrarySong song) async {
    await _library.remove(song.entry.sourcePath);
    await _reload();
  }

  Future<void> _removeMissing() async {
    await _library.removeMissing();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final songs = _visibleSongs;
    final missingCount = _songs.where((song) => song.entry.isMissing).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text('音乐库'),
        actions: [
          IconButton(
            onPressed: _working ? null : _refreshFiles,
            tooltip: '检查本地文件',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: _working ? null : _addFiles,
            tooltip: '添加音乐文件',
            icon: const Icon(Icons.library_add_rounded),
          ),
          IconButton(
            onPressed: _working ? null : _addFolder,
            tooltip: '添加音乐文件夹',
            icon: const Icon(Icons.create_new_folder_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Toolbar(
              controller: _searchController,
              songCount: _songs.length,
              visibleCount: songs.length,
              missingCount: missingCount,
              artists: _artists,
              albums: _albums,
              artistFilter: _artistFilter,
              albumFilter: _albumFilter,
              grid: _grid,
              onQueryChanged: (value) => setState(() => _query = value),
              onClearQuery: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              onArtistChanged: (value) => setState(() => _artistFilter = value),
              onAlbumChanged: (value) => setState(() => _albumFilter = value),
              onGridChanged: (value) => setState(() => _grid = value),
              onRemoveMissing: missingCount == 0 ? null : _removeMissing,
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
                      ? _EmptyLibrary(onAddFiles: _addFiles, onAddFolder: _addFolder)
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

class _LibrarySong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? metadata;

  const _LibrarySong({required this.entry, required this.metadata});

  String get fileName => entry.sourcePath.split(Platform.pathSeparator).last;
  String get fallbackTitle => fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
        '',
      );
  String get title => metadata?.resolvedTitle(fallbackTitle) ?? fallbackTitle;
  String? get artist => metadata?.resolvedArtist(null);
  String? get album => metadata?.resolvedAlbum(null);
  String? get artworkPath => metadata?.resolvedArtwork(null);
  bool get hasLyrics => metadata?.metadata['linkedProjectId'] is String;

  String get searchText => [
        title,
        artist ?? '',
        album ?? '',
        fileName,
        entry.sourcePath,
      ].join('\n').toLowerCase();

  PlaybackItem get playbackItem {
    final asset = AudioAsset(
      originalPath: entry.sourcePath,
      format: entry.format,
      thumbnailPath: artworkPath,
    );
    return PlaybackItem(
      id: 'local:${entry.sourcePath}',
      title: title,
      artist: artist,
      artworkPath: artworkPath,
      hasLyrics: hasLyrics,
      audioAsset: asset,
      preferredSource: AudioSourceType.original,
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final int songCount;
  final int visibleCount;
  final int missingCount;
  final List<String> artists;
  final List<String> albums;
  final String artistFilter;
  final String albumFilter;
  final bool grid;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onArtistChanged;
  final ValueChanged<String> onAlbumChanged;
  final ValueChanged<bool> onGridChanged;
  final VoidCallback? onRemoveMissing;

  const _Toolbar({
    required this.controller,
    required this.songCount,
    required this.visibleCount,
    required this.missingCount,
    required this.artists,
    required this.albums,
    required this.artistFilter,
    required this.albumFilter,
    required this.grid,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onArtistChanged,
    required this.onAlbumChanged,
    required this.onGridChanged,
    required this.onRemoveMissing,
  });

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      controller: controller,
      onChanged: onQueryChanged,
      decoration: InputDecoration(
        hintText: '搜索歌曲、艺人、专辑或文件名',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(onPressed: onClearQuery, icon: const Icon(Icons.close_rounded)),
      ),
    );
    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterDropdown(
          value: artistFilter,
          allLabel: '全部艺人',
          icon: Icons.person_rounded,
          values: artists,
          onChanged: onArtistChanged,
        ),
        _FilterDropdown(
          value: albumFilter,
          allLabel: '全部专辑',
          icon: Icons.album_rounded,
          values: albums,
          onChanged: onAlbumChanged,
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded)),
            ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded)),
          ],
          selected: {grid},
          onSelectionChanged: (selection) => onGridChanged(selection.first),
          showSelectedIcon: false,
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
              if (constraints.maxWidth < 820) {
                return Column(
                  children: [
                    search,
                    const SizedBox(height: AppSpacing.sm),
                    Align(alignment: Alignment.centerLeft, child: controls),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: AppSpacing.md),
                  controls,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                visibleCount == songCount ? '$songCount 首歌曲' : '$visibleCount / $songCount 首',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
              if (missingCount > 0)
                Text('$missingCount 个文件不可用', style: const TextStyle(color: AppColors.error)),
              if (missingCount > 0)
                TextButton(onPressed: onRemoveMissing, child: const Text('清理缺失项')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final String allLabel;
  final IconData icon;
  final List<String> values;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.allLabel,
    required this.icon,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.expand_more_rounded),
          items: [
            DropdownMenuItem(value: '', child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(allLabel)])),
            ...values.map((item) => DropdownMenuItem(value: item, child: Text(item))),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _SongGrid extends StatelessWidget {
  final List<_LibrarySong> songs;
  final ValueChanged<_LibrarySong> onPlay;
  final ValueChanged<_LibrarySong> onEnqueue;
  final ValueChanged<_LibrarySong> onEdit;
  final ValueChanged<_LibrarySong> onLyrics;
  final ValueChanged<_LibrarySong> onRemove;

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
          itemBuilder: (context, index) {
            final song = songs[index];
            return _SongCard(
              song: song,
              onPlay: () => onPlay(song),
              onEnqueue: () => onEnqueue(song),
              onEdit: () => onEdit(song),
              onLyrics: () => onLyrics(song),
              onRemove: () => onRemove(song),
            );
          },
        );
      },
    );
  }
}

class _SongList extends StatelessWidget {
  final List<_LibrarySong> songs;
  final ValueChanged<_LibrarySong> onPlay;
  final ValueChanged<_LibrarySong> onEnqueue;
  final ValueChanged<_LibrarySong> onEdit;
  final ValueChanged<_LibrarySong> onLyrics;
  final ValueChanged<_LibrarySong> onRemove;

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
          leading: SizedBox(width: 52, height: 52, child: _Artwork(song: song)),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(song.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: song.entry.isMissing ? null : () => onPlay(song),
          trailing: _SongMenu(
            song: song,
            onEnqueue: () => onEnqueue(song),
            onEdit: () => onEdit(song),
            onLyrics: () => onLyrics(song),
            onRemove: () => onRemove(song),
          ),
        );
      },
    );
  }
}

class _SongCard extends StatelessWidget {
  final _LibrarySong song;
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
          border: Border.all(color: song.entry.isMissing ? AppColors.error.withAlpha(90) : AppColors.borderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(song: song),
                  if (!song.entry.isMissing)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Material(
                        color: AppColors.pureWhite,
                        shape: const CircleBorder(),
                        child: IconButton(onPressed: onPlay, color: AppColors.pureBlack, icon: const Icon(Icons.play_arrow_rounded)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                _SongMenu(song: song, onEnqueue: onEnqueue, onEdit: onEdit, onLyrics: onLyrics, onRemove: onRemove),
              ],
            ),
            Text(
              song.entry.isMissing ? '文件不可用' : (song.artist?.trim().isNotEmpty == true ? song.artist! : '本地音乐'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: song.entry.isMissing ? AppColors.error : AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              [song.entry.format.toUpperCase(), if (song.hasLyrics) '有歌词'].join(' · '),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongMenu extends StatelessWidget {
  final _LibrarySong song;
  final VoidCallback onEnqueue;
  final VoidCallback onEdit;
  final VoidCallback onLyrics;
  final VoidCallback onRemove;

  const _SongMenu({required this.song, required this.onEnqueue, required this.onEdit, required this.onLyrics, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      onSelected: (value) {
        if (value == 'queue') {
          onEnqueue();
        } else if (value == 'edit') {
          onEdit();
        } else if (value == 'lyrics') {
          onLyrics();
        } else if (value == 'remove') {
          onRemove();
        }
      },
      itemBuilder: (context) => [
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
  final _LibrarySong song;

  const _Artwork({required this.song});

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
              child: Icon(
                song.entry.isMissing ? Icons.link_off_rounded : Icons.music_note_rounded,
                color: song.entry.isMissing ? AppColors.error : AppColors.textTertiary,
                size: 48,
              ),
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  const _EmptyLibrary({required this.onAddFiles, required this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_rounded, size: 72, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('建立你的本地音乐库', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '添加文件或整个文件夹。歌曲会保留在 LyricForge 音乐库中，下次打开仍然存在。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(onPressed: onAddFolder, icon: const Icon(Icons.folder_rounded), label: const Text('添加音乐文件夹')),
                OutlinedButton.icon(onPressed: onAddFiles, icon: const Icon(Icons.audio_file_rounded), label: const Text('添加音乐文件')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on _LibrarySong {
  String get subtitle => [
        if (artist?.trim().isNotEmpty == true) artist!,
        if (album?.trim().isNotEmpty == true) album!,
        entry.format.toUpperCase(),
        if (hasLyrics) '有歌词',
        if (entry.isMissing) '文件不可用',
      ].join(' · ');
}
