import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/play_history.dart';
import '../../domain/repositories/play_history_repository.dart';

/// File-backed recent-play history for local audio.
///
/// History is stored under LyricForge's application-support Data directory and
/// rewritten atomically after every mutation. Missing local files are pruned
/// whenever recent history is read so stale cards do not survive indefinitely.
class FilePlayHistoryRepository implements PlayHistoryRepository {
  final Directory? rootDirectory;

  final List<PlayHistory> _histories = <PlayHistory>[];
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();

  FilePlayHistoryRepository({this.rootDirectory});

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
    return File(directory.path + Platform.pathSeparator + 'play_history.json');
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _isRemotePath(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _load() async {
    final file = await _storeFile();
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final entries = decoded['histories'];
      if (entries is! List) return;

      final seenPaths = <String>{};
      for (final entry in entries) {
        if (entry is! Map) continue;
        try {
          final history = PlayHistory.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (_isRemotePath(history.filePath)) continue;
          final key = _pathKey(history.filePath);
          if (!seenPaths.add(key)) continue;
          _histories.add(history);
          if (_histories.length >= maxHistoryCount) break;
        } catch (_) {
          // One malformed history entry should not make the whole local media
          // history unavailable.
        }
      }
      _histories.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    } catch (_) {
      // Recent-play history is recoverable metadata. If the JSON document is
      // malformed, start from an empty in-memory view and overwrite it on the
      // next successful save instead of blocking the app dashboard.
      _histories.clear();
    }
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'histories': _histories
          .take(maxHistoryCount)
          .map((history) => history.toJson())
          .toList(growable: false),
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

  Future<bool> _pruneMissingFiles() async {
    if (_histories.isEmpty) return false;

    var changed = false;
    final retained = <PlayHistory>[];
    for (final history in _histories) {
      if (_isRemotePath(history.filePath)) {
        changed = true;
      } else if (await File(history.filePath).exists()) {
        retained.add(history);
      } else {
        changed = true;
      }
    }

    if (changed) {
      _histories
        ..clear()
        ..addAll(retained);
    }
    return changed;
  }

  @override
  Future<void> savePlayHistory(PlayHistory history) async {
    if (_isRemotePath(history.filePath)) return;
    await _ensureLoaded();
    final key = _pathKey(history.filePath);
    _histories.removeWhere((entry) => _pathKey(entry.filePath) == key);
    _histories.insert(0, history);
    if (_histories.length > maxHistoryCount) {
      _histories.removeRange(maxHistoryCount, _histories.length);
    }
    await _persist();
  }

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    await _ensureLoaded();
    if (await _pruneMissingFiles()) {
      await _persist();
    }
    final safeLimit = limit < 0 ? 0 : limit;
    return _histories.take(safeLimit).toList(growable: false);
  }

  /// Rebinds a recent-play row before normal reads have a chance to prune the
  /// now-missing old path. If the destination already has history, whichever
  /// row was played most recently wins so resume state remains deterministic.
  Future<bool> replaceLocalPath({
    required String oldPath,
    required String newPath,
  }) async {
    await _ensureLoaded();
    final oldKey = _pathKey(oldPath);
    final newAbsolute = File(newPath).absolute.path;
    final newKey = _pathKey(newAbsolute);
    final oldIndex = _histories.indexWhere(
      (history) => _pathKey(history.filePath) == oldKey,
    );
    if (oldIndex < 0) return false;

    final oldHistory = _histories[oldIndex];
    final migrated = oldHistory.copyWith(filePath: newAbsolute);
    final existingIndex = _histories.indexWhere(
      (history) => _pathKey(history.filePath) == newKey,
    );
    PlayHistory retained = migrated;
    if (existingIndex >= 0 && existingIndex != oldIndex) {
      final existing = _histories[existingIndex];
      if (existing.playedAt.isAfter(migrated.playedAt)) retained = existing;
    }

    _histories.removeWhere((history) {
      final key = _pathKey(history.filePath);
      return key == oldKey || key == newKey;
    });
    _histories.add(retained);
    _histories.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    await _persist();
    return true;
  }

  @override
  Future<void> clearPlayHistory() async {
    await _ensureLoaded();
    if (_histories.isEmpty) return;
    _histories.clear();
    await _persist();
  }

  @override
  Future<void> removePlayHistory(String id) async {
    await _ensureLoaded();
    final before = _histories.length;
    _histories.removeWhere((history) => history.id == id);
    if (_histories.length != before) {
      await _persist();
    }
  }

  @override
  Future<PlayHistory?> getPlayHistoryById(String id) async {
    await _ensureLoaded();
    final index = _histories.indexWhere((history) => history.id == id);
    if (index < 0) return null;

    final history = _histories[index];
    if (_isRemotePath(history.filePath)) {
      _histories.removeAt(index);
      await _persist();
      return null;
    }
    if (await File(history.filePath).exists()) return history;

    _histories.removeAt(index);
    await _persist();
    return null;
  }
}
