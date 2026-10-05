import '../../../project/domain/models/audio_asset.dart';

/// Metadata contract for ephemeral remote playback items.
///
/// Remote stream credentials/URLs stay only in the in-memory playback queue.
/// They are never persisted into the local Library or recent-play history.
abstract final class RemotePlaybackSource {
  static const String markerKey = 'remoteMediaHub';
  static const String streamUriKey = 'remoteStreamUri';
  static const String remoteTrackIdKey = 'remoteTrackId';
  static const String remoteTrackKey = 'remoteTrack';

  static bool isRemote(AudioAsset asset) => asset.metadata[markerKey] == true;

  static Uri? streamUri(AudioAsset asset) {
    final raw = asset.metadata[streamUriKey];
    if (raw is! String || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }
}
