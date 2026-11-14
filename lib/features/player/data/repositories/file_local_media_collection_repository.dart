import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/persistence/atomic_json_file.dart';
import '../../../../core/persistence/retryable_load.dart';
import '../../domain/models/local_playlist.dart';
import '../../domain/repositories/local_media_collection_repository.dart';
import '../../domain/repositories/local_store_integrity.dart';
import 'local_store_preservation.dart';

/// Persists favorites and playlists in `library_collections.json`.
///
/// Shares the library store's load contract: an unreadable file throws and is
/// retried on the next call (#440); unreadable favorites or playlists keep the
/// readable ones visible but block every write until the user repairs the
/// store, so a toggle can never drop the rows that failed to load (#439).
class FileLocalMediaCollectionRepository
    implements LocalMediaCollectionRepository, LocalStoreIntegrity {
  static const int _schemaVersion = 1;

  static final AtomicJsonValidator _isValidStoreJson = AtomicJsonFile.versioned(
    currentVersion: _schemaVersion,
    validate: _isValidPayloadJson,
  );

  static bool _isValidPayloadJson(Object? decoded) =>
      decoded is Map &&
      (decoded['favorites'] is List || decoded['playlists'] is List) &&
      (decoded['favorites'] == null || decoded['favorites'] is List) &&
      (decoded['playlists'] == null || decoded['playlists'] is List);

  final Directory? rootDirectory;

  final List<String> _favoritePaths = <String>[];
  final List<LocalPlaylist> _playlists = <LocalPlaylist>[];
  final StreamController<int> _changeController =
      StreamController<int>.broadcast();
  late final RetryableLoad _loader = RetryableLoad(_load);
  Future<void> _writeChain = Future<void>.value();
  int _revision = 0;
  LocalStoreLoadIssue? _loadIssue;

  FileLocalMediaCollectionRepository({this.rootDirectory});

  @override
  Stream<int> get changes => _changeController.stream;

  Future<void> _ensureLoaded() => _loader.ensureLoaded();

  /// Loads, then refuses to continue a mutation of a partly read store.
  Future<void> _ensureWritable() async {
    await _ensureLoaded();
    final issue = _loadIssue;
    if (issue != null) throw LocalStoreIncompleteException(issue);
  }

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}library_collections.json',
    );
  }

  String _canonicalPath(String path) => File(path).absolute.path;

  String _pathKey(String path) {
    final canonical = _canonicalPath(path);
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _load() async {
    final file = await _storeFile();
    await AtomicJsonFile.recoverIfNeeded(file, validate: _isValidStoreJson);
    if (await file.exists() &&
        !await AtomicJsonFile.isValidJsonFile(
          file,
          validate: _isValidStoreJson,
        )) {
      throw FormatException(
        'The local media collections are invalid and no recoverable copy is available. ${file.path}',
      );
    }
    if (!await file.exists()) {
      _commitLoad(const [], const [], null);
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (error) {
      throw FormatException(
        'The local media collections could not be read completely: $error',
        file.path,
      );
    }
    if (!_isValidStoreJson(decoded)) {
      throw FormatException(
        'The local media collections changed or became invalid while loading.',
        file.path,
      );
    }
    final payload = decoded as Map;

    final favorites = <String>[];
    final playlists = <LocalPlaylist>[];
    var unreadable = 0;
    String? firstProblem;
    void skip(String problem) {
      unreadable += 1;
      firstProblem ??= problem;
    }

    final rawFavorites = payload['favorites'];
    if (rawFavorites is List) {
      final seen = <String>{};
      for (var index = 0; index < rawFavorites.length; index++) {
        final raw = rawFavorites[index];
        if (raw is! String) {
          skip('Favorite ${index + 1} is not a path.');
          continue;
        }
        if (raw.trim().isEmpty) continue;
        final canonical = _canonicalPath(raw);
        if (seen.add(_pathKey(canonical))) favorites.add(canonical);
      }
    }

    final rawPlaylists = payload['playlists'];
    if (rawPlaylists is List) {
      final seenIds = <String>{};
      for (var index = 0; index < rawPlaylists.length; index++) {
        final raw = rawPlaylists[index];
        try {
          if (raw is! Map) throw const FormatException('Not an object');
          final parsed = LocalPlaylist.fromJson(Map<String, dynamic>.from(raw));
          if (parsed.id.trim().isEmpty || parsed.name.trim().isEmpty) {
            throw const FormatException('Missing playlist id or name');
          }
          // A second playlist with the same id is distinct user data; dropping
          // it on the next write would lose its songs.
          if (!seenIds.add(parsed.id)) {
            throw FormatException('Duplicate playlist id ${parsed.id}');
          }

          final seenPaths = <String>{};
          final canonicalPaths = <String>[];
          for (final path in parsed.sourcePaths) {
            if (path.trim().isEmpty) continue;
            final canonical = _canonicalPath(path);
            if (seenPaths.add(_pathKey(canonical))) {
              canonicalPaths.add(canonical);
            }
          }
          playlists.add(
            parsed.copyWith(
              sourcePaths: List<String>.unmodifiable(canonicalPaths),
            ),
          );
        } catch (error) {
          skip('Playlist ${index + 1} could not be read: $error');
        }
      }
    }

    _commitLoad(
      favorites,
      playlists,
      unreadable == 0
          ? null
          : LocalStoreLoadIssue(
              kind: LocalStoreKind.collections,
              storePath: file.path,
              unreadableRecords: unreadable,
              readableRecords: favorites.length + playlists.length,
              detail: firstProblem!,
            ),
    );
  }

  void _commitLoad(
    List<String> favorites,
    List<LocalPlaylist> playlists,
    LocalStoreLoadIssue? issue,
  ) {
    _favoritePaths
      ..clear()
      ..addAll(favorites);
    _playlists
      ..clear()
      ..addAll(playlists);
    _loadIssue = issue;
    _sortPlaylists();
  }

  @override
  Future<LocalStoreLoadIssue?> loadIssue() async {
    await _ensureLoaded();
    return _loadIssue;
  }

  @override
  Future<LocalStoreRepairResult> repairKeepingReadableRecords() async {
    await _ensureLoaded();
    final issue = _loadIssue;
    if (issue == null) {
      throw StateError('The local media collections have no load issue.');
    }
    final preserved = await preserveIncompleteStoreCopy(File(issue.storePath));
    await _persistUnchecked();
    _loadIssue = null;
    _revision += 1;
    _changeController.add(_revision);
    return LocalStoreRepairResult(
      preservedCopyPath: preserved,
      keptRecords: issue.readableRecords,
      droppedRecords: issue.unreadableRecords,
    );
  }

  void _sortPlaylists() {
    _playlists.sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Future<void> _persist() {
    final issue = _loadIssue;
    if (issue != null) {
      return Future<void>.error(LocalStoreIncompleteException(issue));
    }
    return _persistUnchecked();
  }

  Future<void> _persistUnchecked() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': _schemaVersion,
      'favorites': _favoritePaths,
      'playlists': _playlists
          .map((item) => item.toJson())
          .toList(growable: false),
    });

    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed earlier write must not poison all future writes.
      }
      final file = await _storeFile();
      await AtomicJsonFile.write(file, payload, validate: _isValidStoreJson);
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
    await _ensureWritable();
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
    await _ensureWritable();
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
      description: trimmedDescription?.isEmpty == true
          ? null
          : trimmedDescription,
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
    await _ensureWritable();
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
    await _ensureWritable();
    final before = _playlists.length;
    _playlists.removeWhere((item) => item.id == playlistId);
    if (_playlists.length != before) await _persistAndNotify();
  }

  @override
  Future<LocalPlaylist> addToPlaylist(
    String playlistId,
    Iterable<String> sourcePaths,
  ) async {
    await _ensureWritable();
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
    await _ensureWritable();
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
    await _ensureWritable();
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
