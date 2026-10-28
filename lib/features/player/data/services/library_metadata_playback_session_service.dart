import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_library_repository.dart';
import '../../domain/services/playback_session_service.dart';

/// Enriches playback items before delegating to the normal app-scoped session.
///
/// Local music receives cached embedded tags first; the delegate then applies
/// explicit user metadata overrides. Remote Media Hub items keep playback fast,
/// while their artwork is hydrated asynchronously into app-owned storage. Once
/// cached, the queue item is updated with a local artwork path so Now Playing,
/// queue rows and platform lock-screen metadata all use the same image source.
class LibraryMetadataPlaybackSessionService implements PlaybackSessionService {
  static const int _maxArtworkBytes = 16 * 1024 * 1024;
  static const int _maxCachedArtworkFiles = 96;
  static const int _maxConcurrentArtworkDownloads = 3;

  final PlaybackSessionService delegate;
  final LocalMediaLibraryRepository libraryRepository;
  final Directory? remoteArtworkCacheDirectory;

  final Set<String> _scheduledArtworkKeys = <String>{};
  final List<_RemoteArtworkJob> _pendingArtwork = <_RemoteArtworkJob>[];
  int _activeArtworkDownloads = 0;
  bool _disposed = false;

  LibraryMetadataPlaybackSessionService({
    required this.delegate,
    required this.libraryRepository,
    this.remoteArtworkCacheDirectory,
  });

  @override
  Stream<PlaybackSessionState> get stateStream => delegate.stateStream;

  @override
  PlaybackSessionState get currentState => delegate.currentState;

  @override
  PlaybackState get playbackState => delegate.playbackState;

  Future<PlaybackItem> _enrich(PlaybackItem item) async {
    if (item.projectId != null || item.isRemoteStream) return item;
    LocalMediaLibraryEntry? entry;
    try {
      entry = await libraryRepository.getByPath(item.audioAsset.originalPath);
    } catch (_) {
      return item;
    }
    if (entry == null) return item;

    final title = entry.embeddedTitle?.trim();
    final artist = entry.embeddedArtist?.trim();
    final artwork = entry.embeddedArtworkPath?.trim();
    return item.copyWith(
      title: title == null || title.isEmpty ? item.title : title,
      artist: artist == null || artist.isEmpty ? item.artist : artist,
      artworkPath: artwork == null || artwork.isEmpty ? item.artworkPath : artwork,
    );
  }

  Future<List<PlaybackItem>> _enrichAll(List<PlaybackItem> items) async {
    final result = <PlaybackItem>[];
    for (final item in items) {
      result.add(await _enrich(item));
    }
    return result;
  }

  Uri? _remoteArtworkUri(PlaybackItem item) {
    if (!item.isRemoteStream) return null;
    final raw = item.audioAsset.metadata['remoteArtworkUri'];
    if (raw is! String || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  bool _hasUsableLocalArtwork(PlaybackItem item) {
    final path = item.artworkPath?.trim();
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  void _scheduleRemoteArtwork(PlaybackItem item, {bool prioritize = false}) {
    if (_disposed) return;
    final uri = _remoteArtworkUri(item);
    if (uri == null || _hasUsableLocalArtwork(item)) return;

    final key = '${item.id}|$uri';
    if (_scheduledArtworkKeys.contains(key)) {
      if (prioritize) {
        final index = _pendingArtwork.indexWhere((job) => job.key == key);
        if (index > 0) {
          final job = _pendingArtwork.removeAt(index);
          _pendingArtwork.insert(0, job);
        }
      }
      return;
    }

    final job = _RemoteArtworkJob(key: key, item: item, uri: uri);
    _scheduledArtworkKeys.add(key);
    if (prioritize) {
      _pendingArtwork.insert(0, job);
    } else {
      _pendingArtwork.add(job);
    }
    _pumpArtworkQueue();
  }

  void _scheduleQueueArtwork(
    Iterable<PlaybackItem> items, {
    String? prioritizedItemId,
  }) {
    PlaybackItem? prioritized;
    final remainder = <PlaybackItem>[];
    for (final item in items) {
      if (item.id == prioritizedItemId) {
        prioritized = item;
      } else {
        remainder.add(item);
      }
    }
    if (prioritized != null) {
      _scheduleRemoteArtwork(prioritized, prioritize: true);
    }
    for (final item in remainder) {
      _scheduleRemoteArtwork(item);
    }
  }

  void _pumpArtworkQueue() {
    if (_disposed) return;
    while (_activeArtworkDownloads < _maxConcurrentArtworkDownloads &&
        _pendingArtwork.isNotEmpty) {
      final job = _pendingArtwork.removeAt(0);
      _activeArtworkDownloads++;
      unawaited(
        _hydrateRemoteArtwork(job.item, job.uri).whenComplete(() {
          _activeArtworkDownloads--;
          _scheduledArtworkKeys.remove(job.key);
          _pumpArtworkQueue();
        }),
      );
    }
  }

  Future<Directory> _artworkDirectory() async {
    final configured = remoteArtworkCacheDirectory;
    if (configured != null) {
      await configured.create(recursive: true);
      return configured;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}LyricForge'
      '${Platform.pathSeparator}Cache${Platform.pathSeparator}RemoteArtwork',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _cacheKey(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _extensionFor(ContentType? contentType) {
    final mime = contentType?.mimeType.toLowerCase();
    return switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/bmp' => 'bmp',
      'image/jpeg' || 'image/jpg' => 'jpg',
      _ => 'img',
    };
  }

  Future<File?> _findCachedArtwork(Directory directory, String prefix) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? entity.path
            : entity.uri.pathSegments.last;
        if (!name.startsWith(prefix) || name.endsWith('.part')) continue;
        if (await entity.length() <= 0) continue;
        return entity;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _hydrateRemoteArtwork(PlaybackItem item, Uri uri) async {
    File? partial;
    HttpClient? client;
    try {
      final directory = await _artworkDirectory();
      final prefix = 'remote_${_cacheKey(uri.toString())}.';
      final cached = await _findCachedArtwork(directory, prefix);
      if (cached != null) {
        await _applyCachedArtwork(item.id, uri, cached.path);
        return;
      }

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return;
      }
      final contentType = response.headers.contentType;
      final mime = contentType?.mimeType.toLowerCase();
      if (mime != null && !mime.startsWith('image/')) {
        await response.drain<void>();
        return;
      }
      final advertisedLength = response.contentLength;
      if (advertisedLength > _maxArtworkBytes) {
        await response.drain<void>();
        return;
      }

      final extension = _extensionFor(contentType);
      final destination =
          File('${directory.path}${Platform.pathSeparator}$prefix$extension');
      partial = File('${destination.path}.part');
      if (await partial.exists()) await partial.delete();

      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (received > _maxArtworkBytes) {
            throw const FormatException('remote artwork exceeds size limit');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0) {
        if (await partial.exists()) await partial.delete();
        return;
      }
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
      partial = null;

      await _applyCachedArtwork(item.id, uri, destination.path);
      unawaited(_pruneArtworkCache(directory));
    } catch (_) {
      if (partial != null && await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      // Artwork is cosmetic. A failed cover request must never block playback.
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _applyCachedArtwork(
    String itemId,
    Uri expectedRemoteUri,
    String path,
  ) async {
    if (_disposed) return;
    PlaybackItem? current;
    for (final candidate in delegate.currentState.queue) {
      if (candidate.id == itemId) {
        current = candidate;
        break;
      }
    }
    if (current == null) return;
    final currentRemoteUri = _remoteArtworkUri(current);
    if (currentRemoteUri != expectedRemoteUri) return;
    if (_hasUsableLocalArtwork(current)) return;

    await delegate.updateItem(
      current.copyWith(
        artworkPath: path,
        audioAsset: current.audioAsset.copyWith(thumbnailPath: path),
      ),
    );
  }

  Future<void> _pruneArtworkCache(Directory directory) async {
    try {
      final files = await directory
          .list(followLinks: false)
          .where((entity) => entity is File && !entity.path.endsWith('.part'))
          .cast<File>()
          .toList();
      if (files.length <= _maxCachedArtworkFiles) return;

      final dated = <({File file, DateTime modified})>[];
      for (final file in files) {
        dated.add((file: file, modified: await file.lastModified()));
      }
      dated.sort((a, b) => b.modified.compareTo(a.modified));
      for (final entry in dated.skip(_maxCachedArtworkFiles)) {
        try {
          await entry.file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _prioritizeCurrentArtwork() {
    final current = delegate.currentState.currentItem;
    if (current != null) _scheduleRemoteArtwork(current, prioritize: true);
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    final enriched = await _enrich(item);
    await delegate.playItem(enriched, resumeFrom: resumeFrom);
    _scheduleRemoteArtwork(
      delegate.currentState.currentItem ?? enriched,
      prioritize: true,
    );
  }

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    final enriched = await _enrichAll(items);
    await delegate.setQueue(enriched, startIndex: startIndex);
    _scheduleQueueArtwork(
      delegate.currentState.queue,
      prioritizedItemId: delegate.currentState.currentItem?.id,
    );
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final enriched = await _enrich(item);
    await delegate.enqueue(enriched);
    _scheduleRemoteArtwork(enriched);
  }

  @override
  Future<void> updateItem(PlaybackItem item) async {
    await delegate.updateItem(item);
    _scheduleRemoteArtwork(item);
  }

  @override
  Future<void> playAt(int index) async {
    await delegate.playAt(index);
    _prioritizeCurrentArtwork();
  }

  @override
  Future<void> removeAt(int index) => delegate.removeAt(index);

  @override
  Future<void> moveItem(int oldIndex, int newIndex) =>
      delegate.moveItem(oldIndex, newIndex);

  @override
  Future<void> clearQueue({bool keepCurrent = true}) =>
      delegate.clearQueue(keepCurrent: keepCurrent);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      delegate.setShuffleEnabled(enabled);

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) =>
      delegate.setRepeatMode(mode);

  @override
  Future<void> skipPrevious() async {
    await delegate.skipPrevious();
    _prioritizeCurrentArtwork();
  }

  @override
  Future<void> skipNext() async {
    await delegate.skipNext();
    _prioritizeCurrentArtwork();
  }

  @override
  Future<void> togglePlayPause() => delegate.togglePlayPause();

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pendingArtwork.clear();
    _scheduledArtworkKeys.clear();
    await delegate.dispose();
  }
}

class _RemoteArtworkJob {
  final String key;
  final PlaybackItem item;
  final Uri uri;

  const _RemoteArtworkJob({
    required this.key,
    required this.item,
    required this.uri,
  });
}
