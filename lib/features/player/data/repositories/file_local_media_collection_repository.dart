import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';

class FileLocalMediaCollectionRepository
    implements LocalMediaCollectionRepository {
  final Directory? rootDirectory;

  final List<String> _favoritePaths = <String>[];
  final List<LocalPlaylist> _playlists = <LocalPlaylist>[];
  final StreamController<int> _changeController =
      StreamController<int>.broadcast();
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();
  int _revision = 0;

  FileLocalMediaCollectionRepository({this.rootDirectory});

  @override
  Stream<int> get changes => _changeController.stream;

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      support.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File(
      directory.path + Platform.pathSeparator + 'library_collections.json',
    );
  }

  String _canonicalPath(String path) => File(path).absolute.path;

  String _pathKey(String path) {
    final canonical = _canonicalPath(path);
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _load() async {
    final file = await _storeFile();
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      final rawFavorites = decoded['favorites'];
      if (rawFavorites is List) {
        final seen = <String>{};
        for (final raw in rawFavorites) {
          if (raw is! String || raw.trim().isEmpty) continue;
          final canonical = _canonicalPath(raw);
          if (seen.add(_pathKey(canonical))) {
            _favoritePaths.add(canonical);
          }
        }
      }

      final rawPlaylists = decoded['playlists'];
      if (rawPlaylists is List) {
        final seenIds = <String>{};
        for (final raw in rawPlaylists) {
          if (raw is! Map) continue;
          try {
            final parsed = LocalPlaylist.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (parsed.id.trim().isEmpty || parsed.name.trim().isEmpty) {
              continue;
            }
            if (!seenIds.add(parsed.id)) continue;

            final seenPaths = <String>{};
            final canonicalPaths = <String>[];
            for (final path in parsed.sourcePaths) {
              if (path.trim().isEmpty) continue;
              final canonical = _canonicalPath(path);
              if (seenPaths.add(_pathKey(canonical))) {
                canonicalPaths.add(canonical);
              }
            }
            _playlists.add(
              parsed.copyWith(sourcePaths: List<String>.unmodifiable(canonicalPaths)),
            );
          } catch (_) {
            // Keep the rest of the collection file usable when one row is bad.
          }
        }
      }
      _sortPlaylists();
    } catch (_) {
      _favoritePaths.clear();
      _playlists.clear();
    }
  }

  void _sortPlaylists() {
    _playlists.sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'favorites': _favoritePaths,
      'playlists': _playlists.map((item) => item.toJson()).toList(growable: false),
    });

    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed earlier write must not poison all future writes.
      }
      final file = await _storeFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  Future<void> _persistAndNotify() async {
    await _persist();
    _revision += 1;
    _changeController.add(_revision);
  }

  int _playlistIndex(String playlistId) {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index < 0) {
      throw StateError('Playlist not found: $playlistId');
    }
    return index;
  }

  @override
  Future<Set<String>> getFavoritePaths() async {
    await _ensureLoaded();
    return Set<String>.unmodifiable(_favoritePaths);
  }

  @override
  Future<bool> isFavorite(String sourcePath) async {
    await _ensureLoaded();
    final key = _pathKey(sourcePath);
    return _favoritePaths.any((path) => _pathKey(path) == key);
  }

  @override
  Future<bool> setFavorite(String sourcePath, bool favorite) async {
    await _ensureLoaded();
    if (sourcePath.trim().isEmpty) return false;

    final canonical = _canonicalPath(sourcePath);
    final key = _pathKey(canonical);
    final index = _favoritePaths.indexWhere((path) => _pathKey(path) == key);
    var changed = false;

    if (favorite && index < 0) {
      _favoritePaths.add(canonical);
      changed = true;
    } else if (!favorite && index >= 0) {
      _favoritePaths.removeAt(index);
      changed = true;
    }

    if (changed) await _persistAndNotify();
    return favorite;
  }

  @override
  Future<bool> toggleFavorite(String sourcePath) async {
    final current = await isFavorite(sourcePath);
    return setFavorite(sourcePath, !current);
  }

  @override
  Future<List<LocalPlaylist>> getPlaylists() async {
    await _ensureLoaded();
    return List<LocalPlaylist>.unmodifiable(_playlists);
  }

  @override
  Future<LocalPlaylist> createPlaylist(
    String name, {
    String? description,
  }) async {
    await _ensureLoaded();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty');
    }

    final now = DateTime.now();
    var id = 'playlist-${now.microsecondsSinceEpoch}';
    var suffix = 2;
    while (_playlists.any((item) => item.id == id)) {
      id = 'playlist-${now.microsecondsSinceEpoch}-$suffix';
      suffix += 1;
    }

    final trimmedDescription = description?.trim();
    final playlist = LocalPlaylist(
      id: id,
      name: trimmed,
      description: trimmedDescription?.isEmpty == true ? null : trimmedDescription,
      sourcePaths: const [],
      createdAt: now,
      updatedAt: now,
    );
    _playlists.add(playlist);
    _sortPlaylists();
    await _persistAndNotify();
    return playlist;
  }

  @override
  Future<LocalPlaylist> renamePlaylist(String playlistId, String name) async {
    await _ensureLoaded();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty');
    }
    final index = _playlistIndex(playlistId);
    final updated = _playlists[index].copyWith(
      name: trimmed,
      updatedAt: DateTime.now(),
    );
    _playlists[index] = updated;
    _sortPlaylists();
    await _persistAndNotify();
    return updated;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _ensureLoaded();
    final before = _playlists.length;
    _playlists.removeWhere((item) => item.id == playlistId);
    if (_playlists.length != before) await _persistAndNotify();
  }

  @override
  Future<LocalPlaylist> addToPlaylist(
    String playlistId,
    Iterable<String> sourcePaths,
  ) async {
    await _ensureLoaded();
    final index = _playlistIndex(playlistId);
    final current = _playlists[index];
    final paths = List<String>.from(current.sourcePaths);
    final seen = <String>{for (final path in paths) _pathKey(path)};
    var changed = false;

    for (final raw in sourcePaths) {
      if (raw.trim().isEmpty) continue;
      final canonical = _canonicalPath(raw);
      if (seen.add(_pathKey(canonical))) {
        paths.add(canonical);
        changed = true;
      }
    }

    if (!changed) return current;
    final updated = current.copyWith(
      sourcePaths: List<String>.unmodifiable(paths),
      updatedAt: DateTime.now(),
    );
    _playlists[index] = updated;
    _sortPlaylists();
    await _persistAndNotify();
    return updated;
  }

  @override
  Future<LocalPlaylist> removeFromPlaylist(
    String playlistId,
    String sourcePath,
  ) async {
    await _ensureLoaded();
    final index = _playlistIndex(playlistId);
    final current = _playlists[index];
    final key = _pathKey(sourcePath);
    final paths = current.sourcePaths
        .where((path) => _pathKey(path) != key)
        .toList(growable: false);
    if (paths.length == current.sourcePaths.length) return current;

    final updated = current.copyWith(
      sourcePaths: List<String>.unmodifiable(paths),
      updatedAt: DateTime.now(),
    );
    _playlists[index] = updated;
    _sortPlaylists();
    await _persistAndNotify();
    return updated;
  }

  @override
  Future<LocalPlaylist> moveInPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await _ensureLoaded();
    final playlistIndex = _playlistIndex(playlistId);
    final current = _playlists[playlistIndex];
    final paths = List<String>.from(current.sourcePaths);
    if (oldIndex < 0 || oldIndex >= paths.length) {
      throw RangeError.index(oldIndex, paths, 'oldIndex');
    }
    if (newIndex < 0 || newIndex >= paths.length) {
      throw RangeError.index(newIndex, paths, 'newIndex');
    }
    if (oldIndex == newIndex) return current;

    final moved = paths.removeAt(oldIndex);
    paths.insert(newIndex, moved);
    final updated = current.copyWith(
      sourcePaths: List<String>.unmodifiable(paths),
      updatedAt: DateTime.now(),
    );
    _playlists[playlistIndex] = updated;
    _sortPlaylists();
    await _persistAndNotify();
    return updated;
  }
}
