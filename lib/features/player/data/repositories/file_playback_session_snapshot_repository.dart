import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/playback_session_snapshot.dart';
import '../../domain/repositories/playback_session_snapshot_repository.dart';

class FilePlaybackSessionSnapshotRepository
    implements PlaybackSessionSnapshotRepository {
  final Directory? rootDirectory;
  Future<void> _writeChain = Future<void>.value();

  FilePlaybackSessionSnapshotRepository({this.rootDirectory});

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
      directory.path + Platform.pathSeparator + 'playback_session.json',
    );
  }

  @override
  Future<PlaybackSessionSnapshot?> load() async {
    final file = await _storeFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final snapshot = PlaybackSessionSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final pruned = _pruneMissing(snapshot);
      if (pruned == null) {
        await clear();
        return null;
      }
      if (pruned.items.length != snapshot.items.length ||
          pruned.currentIndex != snapshot.currentIndex) {
        await save(pruned);
      }
      return pruned;
    } catch (_) {
      return null;
    }
  }

  PlaybackSessionSnapshot? _pruneMissing(PlaybackSessionSnapshot snapshot) {
    if (snapshot.items.isEmpty) return null;
    final retained = <PlaybackSessionItemSnapshot>[];
    final originalIndices = <int>[];
    for (var i = 0; i < snapshot.items.length; i++) {
      final item = snapshot.items[i];
      if (File(item.audioAsset.originalPath).existsSync()) {
        retained.add(item);
        originalIndices.add(i);
      }
    }
    if (retained.isEmpty) return null;

    var currentIndex = originalIndices.indexOf(snapshot.currentIndex);
    if (currentIndex < 0) {
      currentIndex = originalIndices.indexWhere(
        (index) => index > snapshot.currentIndex,
      );
      if (currentIndex < 0) currentIndex = retained.length - 1;
    }

    return PlaybackSessionSnapshot(
      items: List.unmodifiable(retained),
      currentIndex: currentIndex.clamp(0, retained.length - 1).toInt(),
      position: snapshot.position,
      shuffleEnabled: snapshot.shuffleEnabled,
      repeatMode: snapshot.repeatMode,
      savedAt: snapshot.savedAt,
    );
  }

  @override
  Future<void> save(PlaybackSessionSnapshot snapshot) {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      ...snapshot.toJson(),
    });
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}
      final file = await _storeFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  @override
  Future<void> clear() {
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}
      final file = await _storeFile();
      final temporary = File('${file.path}.tmp');
      if (await temporary.exists()) await temporary.delete();
      if (await file.exists()) await file.delete();
    }();
    _writeChain = operation;
    return operation;
  }
}
