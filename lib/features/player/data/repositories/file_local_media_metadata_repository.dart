import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/persistence/atomic_json_file.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';

class FileLocalMediaMetadataRepository implements LocalMediaMetadataRepository {
  static const int _schemaVersion = 1;

  static final AtomicJsonValidator _isValidStoreJson = AtomicJsonFile.versioned(
    currentVersion: _schemaVersion,
    validate: _isValidPayloadJson,
  );

  static bool _isValidPayloadJson(Object? decoded) =>
      decoded is Map && decoded['items'] is List;

  final Directory? rootDirectory;

  final Map<String, LocalMediaMetadata> _entries = {};
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();
  FormatException? _incompleteLoad;

  FileLocalMediaMetadataRepository({this.rootDirectory});

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

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
      '${directory.path}${Platform.pathSeparator}media_metadata.json',
    );
  }

  Future<Directory> _artworkDirectory() async {
    final directory = await _dataDirectory();
    final artwork = Directory(
      '${directory.path}${Platform.pathSeparator}MediaArtwork',
    );
    await artwork.create(recursive: true);
    return artwork;
  }

  String _normalizedPath(String path) {
    final absolute = File(path).absolute.path;
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  String _key(String sourcePath) => _normalizedPath(sourcePath);

  Future<void> _load() async {
    final file = await _storeFile();
    await AtomicJsonFile.recoverIfNeeded(file, validate: _isValidStoreJson);
    if (await file.exists() &&
        !await AtomicJsonFile.isValidJsonFile(
          file,
          validate: _isValidStoreJson,
        )) {
      throw FormatException(
        'The local media metadata is invalid and no recoverable copy is available. ${file.path}',
      );
    }
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      if (!_isValidStoreJson(decoded)) {
        _incompleteLoad = FormatException(
          'Local media metadata changed or became invalid while loading. '
          'Writes are disabled to preserve the original file.',
          file.path,
        );
        return;
      }

      final items = (decoded as Map)['items'] as List;
      for (var index = 0; index < items.length; index++) {
        final raw = items[index];
        try {
          if (raw is! Map ||
              (raw['metadata'] != null && raw['metadata'] is! Map)) {
            throw const FormatException('Invalid metadata record');
          }
          final entry = LocalMediaMetadata.fromJson(
            Map<String, dynamic>.from(raw),
          );
          _entries[_key(entry.sourcePath)] = entry;
        } catch (_) {
          // Keep valid entries readable but never persist a partial snapshot.
          _incompleteLoad ??= FormatException(
            'Local media metadata record ${index + 1} could not be read. '
            'Writes are disabled to preserve the original file.',
            file.path,
          );
        }
      }
    } catch (_) {
      _incompleteLoad = FormatException(
        'Local media metadata could not be read completely. '
        'Writes are disabled to preserve the original file.',
        file.path,
      );
    }
  }

  void _ensureWritable() {
    final problem = _incompleteLoad;
    if (problem != null) throw problem;
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': _schemaVersion,
      'encoding': 'utf-8',
      'items': _entries.values.map((entry) => entry.toJson()).toList(),
    });
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}

      final file = await _storeFile();
      await AtomicJsonFile.write(file, payload, validate: _isValidStoreJson);
    }();
    _writeChain = operation;
    return operation;
  }

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async {
    await _ensureLoaded();
    return _entries[_key(sourcePath)];
  }

  @override
  Future<List<LocalMediaMetadata>> getAll() async {
    await _ensureLoaded();
    final values = _entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async {
    await _ensureLoaded();
    _ensureWritable();
    final normalizedPath = File(metadata.sourcePath).absolute.path;
    final saved = metadata.copyWith(
      sourcePath: normalizedPath,
      updatedAt: DateTime.now(),
    );
    _entries[_key(normalizedPath)] = saved;
    await _persist();
    return saved;
  }

  @override
  Future<void> removeForAudio(String sourcePath) async {
    await _ensureLoaded();
    _ensureWritable();
    final removed = _entries.remove(_key(sourcePath));
    if (removed == null) return;
    await _persist();
  }

  @override
  Future<String> importArtwork({
    required String sourcePath,
    required String imagePath,
  }) async {
    final source = File(imagePath);
    if (!await source.exists()) {
      throw FileSystemException('Artwork file does not exist', imagePath);
    }

    final extension = _safeImageExtension(imagePath);
    final directory = await _artworkDirectory();
    final name = '${_stablePathHash(_key(sourcePath))}$extension';
    final destination = File(directory.path + Platform.pathSeparator + name);
    final temporary = File('${destination.path}.tmp');

    await source.copy(temporary.path);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return destination.path;
  }

  @override
  Future<void> removeManagedArtwork(String? artworkPath) async {
    if (artworkPath == null || artworkPath.trim().isEmpty) return;
    final directory = await _artworkDirectory();
    final artwork = File(artworkPath);
    final parent = _normalizedPath(artwork.parent.path);
    final managedParent = _normalizedPath(directory.path);
    if (parent != managedParent) return;
    if (await artwork.exists()) await artwork.delete();
  }

  String _safeImageExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.img';
    final extension = name.substring(dot).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    return supported.contains(extension) ? extension : '.img';
  }

  String _stablePathHash(String input) {
    var hash = 0x811C9DC5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
