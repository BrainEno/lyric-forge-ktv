import '../../../project/domain/repositories/project_repository.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'playback_lyrics_project_resolver.dart';
import 'playback_session_service.dart';

/// Resolves the lyric project for [item] and mirrors the outcome onto the
/// session queue flag.
///
/// `PlaybackItem.hasLyrics` is a cache that playback surfaces render
/// synchronously, while the resolver is the source of truth. When a lyric
/// project is deleted, or created after the song was enqueued, the cache goes
/// stale. Every place that resolves lyrics therefore writes the corrected flag
/// back through [PlaybackSessionService.updateItem] so the player bar, quick
/// play and Now Playing agree without each of them re-running resolution.
///
/// Remote streams keep the flag owned by the remote catalogue, so they are
/// never rewritten.
Future<PlaybackLyricsResolution> resolveAndSyncPlaybackLyrics({
  required PlaybackItem item,
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository metadataRepository,
  required PlaybackSessionService playbackSession,
}) async {
  final resolution = await resolvePlaybackLyrics(
    item: item,
    projectRepository: projectRepository,
    metadataRepository: metadataRepository,
  );
  if (item.isRemoteStream || resolution.hasLyrics == item.hasLyrics) {
    return resolution;
  }

  try {
    await playbackSession.updateItem(
      item.copyWith(hasLyrics: resolution.hasLyrics),
    );
  } catch (_) {
    // Flag synchronisation is best effort: a failing queue write must not
    // block playback, and the resolution stays authoritative for the caller.
  }
  return resolution;
}
