import 'playback_session_service.dart';

/// Resolves a persisted remote playback item against the currently available
/// remote media source before audio loading begins.
///
/// Implementations may refresh host/port/token-backed stream URLs, metadata and
/// artwork locations while keeping the queue item's stable identity intact.
abstract class RemotePlaybackItemResolver {
  Future<PlaybackItem> resolveForPlayback(PlaybackItem item);
}

class RemotePlaybackResolutionException implements Exception {
  final String message;

  const RemotePlaybackResolutionException(this.message);

  @override
  String toString() => message;
}
