import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/embedded_audio_metadata.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/services/embedded_audio_metadata_reader.dart';

class FileLocalMediaLibraryRepository implements LocalMediaLibraryRepository {
  static const _defaultAudioExtensions = <String>{
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  };

  final Directory? rootDirectory;
  final EmbeddedAudioMetadataReader? metadataReader;
  final List<LocalMediaLibraryEntry> _entries = <LocalMediaLibraryEntry>[];
  final List<String> _roots = <String>[];
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();

  FileLocalMediaLibraryRepository({
    this.rootDirectory,
    this.metadataReader,
  });

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
    return File(directory.path + Platform.pathSeparator + 'media_library.json');
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _directoryKey(String path) {
    final normalized = Directory(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _formatOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  Future<void> _load() async {
    final file = await _storeFile();
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      final rawRoots = decoded['roots'];
      if (rawRoots is List) {
        final seen = <String>{};
        for (final raw in rawRoots) {
          if (raw is! String || raw.trim().isEmpty) continue;
          final root = Directory(raw).absolute.path;
          if (seen.add(_directoryKey(root))) _roots.add(root);
        }
      }

      final rawEntries = decoded['entries'];
      if (rawEntries is List) {
        final seen = <String>{};
        for (final raw in rawEntries) {
          if (raw is! Map) continue;
          try {
            final entry = LocalMediaLibraryEntry.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (seen.add(_pathKey(entry.sourcePath))) _entries.add(entry);
          } catch (_) {
            // Skip one malformed row instead of losing the complete library.
          }
        }
      }
      _sort();
    } catch (_) {
      _entries.clear();
      _roots.clear();
    }
  }

  void _sort() {
    _entries.sort((a, b) {
      if (a.isMissing != b.isMissing) return a.isMissing ? 1 : -1;
      return a.sourcePath.toLowerCase().compareTo(b.sourcePath.toLowerCase());
    });
    _roots.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 3,
      'roots': _roots,
      'entries': _entries.map((entry) => entry.toJson()).toList(growable: false),
    });

    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}
      final file = await _storeFile();
      final temporary = File(file.path + '.tmp');
      await temporary.writeAsString(payload, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async {
    await _ensureLoaded();
    return List<LocalMediaLibraryEntry>.unmodifiable(_entries);
  }

  @override
  Future<LocalMediaLibraryEntry?> getByPath(String sourcePath) async {
    await _ensureLoaded();
    final key = _pathKey(sourcePath);
    for (final entry in _entries) {
      if (_pathKey(entry.sourcePath) == key) return entry;
    }
    return null;
  }

  @override
  Future<List<String>> getRoots() async {
    await _ensureLoaded();
    return List<String>.unmodifiable(_roots);
  }

  @override
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths) async {
    await _ensureLoaded();
    if (await _addPathsLoaded(paths)) {
      _sort();
      await _persist();
    }
    return List<LocalMediaLibraryEntry>.unmodifiable(_entries);
  }

  Future<bool> _addPathsLoaded(Iterable<String> paths) async {
    final now = DateTime.now();
    final indexes = <String, int>{
      for (var i = 0; i < _entries.length; i++)
        _pathKey(_entries[i].sourcePath): i,
    };
    var changed = false;

    for (final rawPath in paths) {
      if (rawPath.trim().isEmpty) continue;
      final file = File(rawPath);
      final path = file.absolute.path;
      final key = _pathKey(path);
      final exists = await file.exists();
      final index = indexes[key];

      if (index == null) {
        var entry = LocalMediaLibraryEntry(
          sourcePath: path,
          format: _formatOf(path),
          addedAt: now,
          lastSeenAt: now,
          isMissing: !exists,
        );
        if (exists) entry = await _refreshEntryMetadata(entry, force: true);
        _entries.add(entry);
        indexes[key] = _entries.length - 1;
        changed = true;
        continue;
      }

      final current = _entries[index];
      var updated = current.copyWith(
        format: current.format.isEmpty ? _formatOf(path) : current.format,
        lastSeenAt: exists ? now : current.lastSeenAt,
        isMissing: !exists,
      );
      if (exists) updated = await _refreshEntryMetadata(updated);
      if (_entryChanged(current, updated)) {
        _entries[index] = updated;
        changed = true;
      }
    }
    return changed;
  }

  bool _entryChanged(
    LocalMediaLibraryEntry before,
    LocalMediaLibraryEntry after,
  ) {
    return jsonEncode(before.toJson()) != jsonEncode(after.toJson());
  }

  Future<LocalMediaLibraryEntry> _refreshEntryMetadata(
    LocalMediaLibraryEntry entry, {
    bool force = false,
  }) async {
    final reader = metadataReader;
    if (reader == null || entry.isMissing) return entry;

    final file = File(entry.sourcePath);
    if (!await file.exists()) return entry.copyWith(isMissing: true);
    final stat = await file.stat();
    final unchanged = entry.metadataScannedAt != null &&
        entry.sourceSizeBytes == stat.size &&
        entry.sourceModifiedAt?.millisecondsSinceEpoch ==
            stat.modified.millisecondsSinceEpoch;
    if (!force && unchanged) return entry;

    try {
      final metadata = await reader.read(entry.sourcePath);
      return _applyEmbeddedMetadata(entry, metadata);
    } catch (_) {
      // A malformed or unsupported tag must never make the audio disappear
      // from the local library. Cache the source fingerprint to avoid parsing
      // the same broken tag on every refresh until the file changes.
      return entry.copyWith(
        sourceSizeBytes: stat.size,
        sourceModifiedAt: stat.modified,
        metadataScannedAt: DateTime.now(),
      );
    }
  }

  LocalMediaLibraryEntry _applyEmbeddedMetadata(
    LocalMediaLibraryEntry entry,
    EmbeddedAudioMetadata metadata,
  ) {
    return entry.copyWith(
      embeddedTitle: metadata.title,
      embeddedArtist: metadata.artist,
      embeddedAlbum: metadata.album,
      embeddedArtworkPath: metadata.artworkPath,
      embeddedGenres: metadata.genres,
      embeddedTrackNumber: metadata.trackNumber,
      embeddedYear: metadata.year,
      durationMs: metadata.duration?.inMilliseconds,
      sourceSizeBytes: metadata.sourceSizeBytes,
      sourceModifiedAt: metadata.sourceModifiedAt,
      metadataScannedAt: metadata.scannedAt,
      clearEmbeddedTitle: metadata.title == null,
      clearEmbeddedArtist: metadata.artist == null,
      clearEmbeddedAlbum: metadata.album == null,
      clearEmbeddedArtwork: metadata.artworkPath == null,
      clearEmbeddedTrackNumber: metadata.trackNumber == null,
      clearEmbeddedYear: metadata.year == null,
      clearDuration: metadata.duration == null,
    );
  }

  @override
  Future<void> addRoot(String rootPath) async {
    await _ensureLoaded();
    if (rootPath.trim().isEmpty) return;
    final root = Directory(rootPath).absolute.path;
    final key = _directoryKey(root);
    if (_roots.any((value) => _directoryKey(value) == key)) return;
    _roots.add(root);
    _sort();
    await _persist();
  }

  @override
  Future<List<LocalMediaLibraryEntry>> refreshAvailability() async {
    await _ensureLoaded();
    await _discoverFromRoots(_defaultAudioExtensions);
    return _refreshKnownAvailability();
  }

  @override
  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  ) async {
    await _ensureLoaded();
    final extensions = supportedExtensions.map((value) => value.toLowerCase()).toSet();
    await _discoverFromRoots(extensions);
    return _refreshKnownAvailability();
  }

  Future<void> _discoverFromRoots(Set<String> extensions) async {
    if (_roots.isEmpty || extensions.isEmpty) return;
    final discovered = <String>[];
    for (final rootPath in _roots) {
      final root = Directory(rootPath);
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (entity is File && extensions.contains(_formatOf(entity.path))) {
            discovered.add(entity.path);
          }
        }
      } on FileSystemException {
        // One inaccessible root should not block the rest of the library.
      }
    }
    if (discovered.isEmpty) return;
    if (await _addPathsLoaded(discovered)) {
      _sort();
      await _persist();
    }
  }

  Future<List<LocalMediaLibraryEntry>> _refreshKnownAvailability() async {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final exists = await File(entry.sourcePath).exists();
      var updated = entry.copyWith(
        isMissing: !exists,
        lastSeenAt: exists ? now : entry.lastSeenAt,
      );
      if (exists) updated = await _refreshEntryMetadata(updated);
      if (_entryChanged(entry, updated)) {
        _entries[i] = updated;
        changed = true;
      }
    }
    if (changed) {
      _sort();
      await _persist();
    }
    return List<LocalMediaLibraryEntry>.unmodifiable(_entries);
  }

  @override
  Future<List<LocalMediaLibraryEntry>> refreshMetadata({bool force = false}) async {
    await _ensureLoaded();
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.isMissing) continue;
      final updated = await _refreshEntryMetadata(entry, force: force);
      if (_entryChanged(entry, updated)) {
        _entries[i] = updated;
        changed = true;
      }
    }
    if (changed) await _persist();
    return List<LocalMediaLibraryEntry>.unmodifiable(_entries);
  }

  @override
  Future<void> remove(String sourcePath) async {
    await _ensureLoaded();
    final key = _pathKey(sourcePath);
    final before = _entries.length;
    _entries.removeWhere((entry) => _pathKey(entry.sourcePath) == key);
    if (_entries.length != before) await _persist();
  }

  @override
  Future<void> removeMissing() async {
    await _ensureLoaded();
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.isMissing);
    if (_entries.length != before) await _persist();
  }
}
