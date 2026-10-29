import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../player/domain/services/remote_playback_item_resolver.dart';

/// Rebinds a persisted Media Hub playback item to the latest usable desktop
/// connection. This deliberately keeps the queue item ID stable so restored
/// queue order/shuffle state survives host or token changes.
class MediaHubRemotePlaybackItemResolver implements RemotePlaybackItemResolver {
  static const Duration _catalogTtl = Duration(seconds: 30);

  final MediaHubClientService client;
  final MediaHubConnectionStore connectionStore;

  String? _catalogConnectionKey;
  DateTime? _catalogLoadedAt;
  List<RemoteAudioTrack>? _catalog;

  MediaHubRemotePlaybackItemResolver({
    required this.client,
    required this.connectionStore,
  });

  @override
  Future<PlaybackItem> resolveForPlayback(PlaybackItem item) async {
    if (!item.isRemoteStream) return item;

    final rawTrackId = item.audioAsset.metadata['remoteTrackId'];
    if (rawTrackId is! String || rawTrackId.trim().isEmpty) {
      // Older/non-Media-Hub remote items cannot be rebound safely. Preserve the
      // original URI so existing behavior remains available.
      return item;
    }
    final trackId = rawTrackId.trim();

    final active = client.currentConnection;
    final saved = await connectionStore.loadLastConnection();
    if (active == null && saved == null) {
      throw const RemotePlaybackResolutionException(
        '没有可用的桌面音乐库连接，请先重新连接桌面端后再播放。',
      );
    }

    Object? lastError;
    for (final connection in _connectionCandidates(active, saved)) {
      try {
        final catalog = await _catalogFor(connection);
        RemoteAudioTrack? track;
        for (final candidate in catalog) {
          if (candidate.id == trackId) {
            track = candidate;
            break;
          }
        }
        if (track == null) {
          throw RemotePlaybackResolutionException(
            '桌面音乐库中已找不到“${item.title}”，请刷新音乐库后重试。',
          );
        }
        return await _rebind(item, track);
      } catch (error) {
        lastError = error;
        _invalidateCatalog();
      }
    }

    final detail = lastError is RemotePlaybackResolutionException
        ? lastError.message
        : '无法重新连接保存的桌面音乐库。';
    throw RemotePlaybackResolutionException(
      '$detail 请确认桌面端 Media Hub 已开启；如果设备自动发现不可用，可以回到“桌面音乐库”重新扫码。',
    );
  }

  List<MediaHubConnection> _connectionCandidates(
    MediaHubConnection? active,
    MediaHubConnection? saved,
  ) {
    final result = <MediaHubConnection>[];
    if (active != null) result.add(active);
    if (saved != null && (active == null || !_sameConnection(active, saved))) {
      result.add(saved);
    }
    return result;
  }

  bool _sameConnection(MediaHubConnection a, MediaHubConnection b) =>
      a.host == b.host &&
      a.port == b.port &&
      a.token == b.token &&
      a.tlsFingerprint == b.tlsFingerprint;

  String _connectionKey(MediaHubConnection connection) =>
      '${connection.host}:${connection.port}:${connection.token}:${connection.tlsFingerprint}';

  bool _catalogIsFresh(MediaHubConnection connection) {
    final loadedAt = _catalogLoadedAt;
    return _catalog != null &&
        loadedAt != null &&
        _catalogConnectionKey == _connectionKey(connection) &&
        DateTime.now().difference(loadedAt) <= _catalogTtl;
  }

  Future<List<RemoteAudioTrack>> _catalogFor(
    MediaHubConnection connection,
  ) async {
    final current = client.currentConnection;
    if (current != null && _catalogIsFresh(current)) return _catalog!;

    // connectTo performs the normal health/protocol check and may transparently
    // discover a new endpoint for the same paired device when host/port/token
    // are stale.
    await client.connectTo(connection);
    final resolvedConnection = client.currentConnection ?? connection;
    final tracks = await client.fetchTracks();
    _catalogConnectionKey = _connectionKey(resolvedConnection);
    _catalogLoadedAt = DateTime.now();
    _catalog = List<RemoteAudioTrack>.unmodifiable(tracks);
    return _catalog!;
  }

  void _invalidateCatalog() {
    _catalogConnectionKey = null;
    _catalogLoadedAt = null;
    _catalog = null;
  }

  Future<PlaybackItem> _rebind(
    PlaybackItem item,
    RemoteAudioTrack track,
  ) async {
    final playbackUri = client.playbackUriFor(track);
    final artworkPath = await _cacheArtwork(track);
    final metadata = <String, dynamic>{
      ...item.audioAsset.metadata,
      'transferSource': 'media-hub-stream',
      'remoteTrackId': track.id,
      if (track.album?.trim().isNotEmpty == true) 'album': track.album!.trim(),
    };
    metadata.remove('remoteArtworkUri');
    if (track.album?.trim().isNotEmpty != true) metadata.remove('album');

    return item.copyWith(
      title: track.title,
      artist: track.artist,
      clearArtist: track.artist?.trim().isNotEmpty != true,
      artworkPath: artworkPath,
      clearArtwork: artworkPath == null,
      hasLyrics: track.hasLyrics,
      streamUri: playbackUri,
      audioAsset: item.audioAsset.copyWith(
        originalPath: playbackUri.toString(),
        format: track.format,
        duration: track.duration,
        metadata: metadata,
      ),
    );
  }

  Future<String?> _cacheArtwork(RemoteAudioTrack track) async {
    if (!track.hasArtwork || track.artworkPath == null) return null;
    try {
      final bytes = await client.fetchArtwork(track);
      if (bytes.isEmpty) return null;
      final root = await _artworkCacheDirectory();
      await root.create(recursive: true);
      final name = sha256.convert(utf8.encode(track.id)).toString();
      final file = File('${root.path}${Platform.pathSeparator}$name.image');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      // Remote artwork is optional: never make audio playback fail solely
      // because a cover could not be fetched or cached.
      return null;
    }
  }

  static Future<Directory>? _fallbackArtworkCache;

  Future<Directory> _artworkCacheDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(
        '${support.path}${Platform.pathSeparator}LyricForge'
        '${Platform.pathSeparator}RemoteArtwork',
      );
    } catch (_) {
      return _fallbackArtworkCache ??= Directory.systemTemp.createTemp(
        'lyricforge-remote-artwork-',
      );
    }
  }
}
