import '../../../player/domain/models/local_media_library_entry.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

enum RemoteCatalogGrouping { artists, albums }

String remoteCatalogGroupKey(
  RemoteAudioTrack track,
  RemoteCatalogGrouping grouping,
) {
  final value = switch (grouping) {
    RemoteCatalogGrouping.artists => track.artist,
    RemoteCatalogGrouping.albums => track.album,
  };
  final trimmed = value?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return grouping == RemoteCatalogGrouping.artists ? '未知艺人' : '未知专辑';
}

Map<String, List<RemoteAudioTrack>> groupRemoteCatalog(
  Iterable<RemoteAudioTrack> tracks,
  RemoteCatalogGrouping grouping,
) {
  final grouped = <String, List<RemoteAudioTrack>>{};
  for (final track in tracks) {
    final key = remoteCatalogGroupKey(track, grouping);
    grouped.putIfAbsent(key, () => <RemoteAudioTrack>[]).add(track);
  }
  final keys = grouped.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final ordered = <String, List<RemoteAudioTrack>>{};
  for (final key in keys) {
    final items = List<RemoteAudioTrack>.from(grouped[key]!);
    items.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    ordered[key] = List<RemoteAudioTrack>.unmodifiable(items);
  }
  return Map<String, List<RemoteAudioTrack>>.unmodifiable(ordered);
}

Uri? remoteArtworkUriFor(
  MediaHubClientService client,
  RemoteAudioTrack track,
) {
  final connection = client.currentConnection;
  final path = track.artworkPath?.trim();
  if (connection == null || !track.hasArtwork || path == null || path.isEmpty) {
    return null;
  }
  final uri = connection.resolve(path);
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'token': connection.token,
    },
  );
}

bool remoteTrackMatchesDownloadedEntry(
  RemoteAudioTrack track,
  LocalMediaLibraryEntry entry,
) {
  final segments = entry.sourcePath.replaceAll('\\', '/').split('/');
  final fileName = segments.isEmpty ? entry.sourcePath : segments.last;
  final id = track.id.trim();
  final suffix = id.length > 8 ? id.substring(0, 8) : id;
  final format = track.format.trim().toLowerCase().isEmpty
      ? 'audio'
      : track.format.trim().toLowerCase();
  return fileName.toLowerCase().endsWith('_${suffix.toLowerCase()}.$format');
}

bool isManagedRemoteDownloadPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized.contains('/lyricforge/downloads/');
}
