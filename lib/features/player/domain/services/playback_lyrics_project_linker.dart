import '../models/local_media_metadata.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'audio_path_canonicalizer.dart';
import 'library_lyrics_pairing.dart';
import 'playback_session_service.dart';

/// Links the song at [audioPath] to the lyric project [projectId].
///
/// A link made here replaces whatever the song was linked to by default, so
/// a record of an automatic pairing (D-034) is dropped unless [pairing]
/// describes this link. Background auto-link callers should set
/// [preserveExistingLink] to avoid replacing another project's association.
class PlaybackLyricsProjectLinkConflictException implements Exception {
  const PlaybackLyricsProjectLinkConflictException({
    required this.existingProjectId,
    required this.requestedProjectId,
  });

  final String existingProjectId;
  final String requestedProjectId;

  @override
  String toString() =>
      'Audio is already linked to project $existingProjectId; '
      'refusing automatic relink to $requestedProjectId.';
}

Future<void> linkPlaybackLyricsProject({
  required String audioPath,
  required String projectId,
  required LocalMediaMetadataRepository metadataRepository,
  required PlaybackSessionService playbackSession,
  required AudioPathCanonicalizer pathCanonicalizer,
  LibraryLyricsPairing? pairing,
  bool preserveExistingLink = false,
}) async {
  if (audioPath.trim().isEmpty || projectId.trim().isEmpty) {
    throw ArgumentError('Audio path and project ID must not be empty.');
  }

  final stored = await readCompleteLocalMediaMetadataForAudio(
    metadataRepository,
    audioPath,
  );
  final metadata =
      stored ??
      LocalMediaMetadata(sourcePath: audioPath, updatedAt: DateTime.now());
  final existingProjectId = metadata.metadata['linkedProjectId'];
  if (preserveExistingLink &&
      existingProjectId is String &&
      existingProjectId.trim().isNotEmpty &&
      existingProjectId.trim() != projectId.trim()) {
    throw PlaybackLyricsProjectLinkConflictException(
      existingProjectId: existingProjectId.trim(),
      requestedProjectId: projectId.trim(),
    );
  }
  await metadataRepository.save(
    metadata.copyWith(
      updatedAt: DateTime.now(),
      metadata: {
        for (final entry in metadata.metadata.entries)
          if (entry.key != LibraryLyricsPairing.metadataKey)
            entry.key: entry.value,
        'linkedProjectId': projectId,
        'hasLyrics': true,
        if (pairing != null) LibraryLyricsPairing.metadataKey: pairing.toJson(),
      },
    ),
  );

  final normalizedAudioPath = pathCanonicalizer.canonicalize(audioPath);
  for (final item in playbackSession.currentState.queue) {
    if (item.isRemoteStream ||
        pathCanonicalizer.canonicalize(item.audioAsset.originalPath) !=
            normalizedAudioPath ||
        item.hasLyrics) {
      continue;
    }
    await playbackSession.updateItem(item.copyWith(hasLyrics: true));
  }
}
