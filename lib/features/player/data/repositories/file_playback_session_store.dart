import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/playback_session_snapshot.dart';
import '../../domain/repositories/playback_session_store.dart';
import '../../domain/services/playback_session_service.dart';

/// File-backed playback-session snapshot stored in the app-private support
/// directory. Writes are atomic and serialized so a process interruption cannot
/// leave a half-written queue document behind.
class FilePlaybackSessionStore implements PlaybackSessionStore {
  final Directory? rootDirectory;

  Future<void> _writeChain = Future<void>.value();

  FilePlaybackSessionStore({this.rootDirectory});

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
      final map = Map<String, dynamic>.from(decoded);
      if ((map['version'] as num?)?.toInt() != 1) return null;

      final rawQueue = map['queue'];
      if (rawQueue is! List) return null;

      final queue = <PlaybackItem>[];
      for (final raw in rawQueue) {
        if (raw is! Map) continue;
        try {
          queue.add(_itemFromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {
          // One stale/malformed queue item must not discard the rest of the
          // user's restorable session.
        }
      }

      if (queue.isEmpty) return null;

      final rawIndex = (map['currentIndex'] as num?)?.toInt() ?? 0;
      final currentIndex = rawIndex.clamp(0, queue.length - 1).toInt();
      final shuffleEnabled = map['shuffleEnabled'] as bool? ?? false;
      final repeatMode = _repeatModeFor(map['repeatMode'] as String?);
      final rawOrder = map['unshuffledOrder'];
      final unshuffledOrder = rawOrder is List
          ? rawOrder.whereType<String>().toList(growable: false)
          : null;
      final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
      final savedAtRaw = map['savedAt'] as String?;
      final savedAt = savedAtRaw == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse(savedAtRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0);

      return PlaybackSessionSnapshot(
        state: PlaybackSessionState(
          queue: List<PlaybackItem>.unmodifiable(queue),
          currentIndex: currentIndex,
          shuffleEnabled: shuffleEnabled,
          repeatMode: repeatMode,
        ),
        position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
        unshuffledOrder: unshuffledOrder,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  PlaybackRepeatMode _repeatModeFor(String? name) {
    for (final mode in PlaybackRepeatMode.values) {
      if (mode.name == name) return mode;
    }
    return PlaybackRepeatMode.off;
  }

  AudioSourceType _sourceFor(String? name) {
    for (final source in AudioSourceType.values) {
      if (source.name == name) return source;
    }
    return AudioSourceType.original;
  }

  @override
  Future<void> save(PlaybackSessionSnapshot snapshot) {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'savedAt': snapshot.savedAt.toIso8601String(),
      'positionMs': snapshot.position.inMilliseconds,
      'currentIndex': snapshot.state.currentIndex,
      'shuffleEnabled': snapshot.state.shuffleEnabled,
      'repeatMode': snapshot.state.repeatMode.name,
      'unshuffledOrder': snapshot.unshuffledOrder,
      'queue': snapshot.state.queue.map(_itemToJson).toList(growable: false),
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
      if (await file.exists()) await file.delete();
      final temporary = File('${file.path}.tmp');
      if (await temporary.exists()) await temporary.delete();
    }();
    _writeChain = operation;
    return operation;
  }

  Map<String, dynamic> _itemToJson(PlaybackItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'artist': item.artist,
      'projectId': item.projectId,
      'artworkPath': item.artworkPath,
      'hasLyrics': item.hasLyrics,
      'preferredSource': item.preferredSource.name,
      'streamUri': item.streamUri?.toString(),
      'audioAsset': item.audioAsset.toJson(),
    };
  }

  PlaybackItem _itemFromJson(Map<String, dynamic> json) {
    final preferredSource = _sourceFor(json['preferredSource'] as String?);
    final rawStreamUri = json['streamUri'] as String?;
    final streamUri = rawStreamUri == null || rawStreamUri.trim().isEmpty
        ? null
        : Uri.tryParse(rawStreamUri.trim());
    final rawAsset = json['audioAsset'];
    if (rawAsset is! Map) {
      throw const FormatException('missing audioAsset');
    }

    return PlaybackItem(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      projectId: json['projectId'] as String?,
      artworkPath: json['artworkPath'] as String?,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
      preferredSource: preferredSource,
      streamUri: streamUri,
      audioAsset: AudioAsset.fromJson(Map<String, dynamic>.from(rawAsset)),
    );
  }
}
