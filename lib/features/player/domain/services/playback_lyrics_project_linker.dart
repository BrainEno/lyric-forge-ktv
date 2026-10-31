import '../models/local_media_metadata.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'audio_path_canonicalizer.dart';
import 'playback_session_service.dart';

Future<void> linkPlaybackLyricsProject({
  required String audioPath,
  required String projectId,
  required LocalMediaMetadataRepository metadataRepository,
  required PlaybackSessionService playbackSession,
  required AudioPathCanonicalizer pathCanonicalizer,
}) async {
  if (audioPath.trim().isEmpty || projectId.trim().isEmpty) {
    throw ArgumentError('Audio path and project ID must not be empty.');
  }

  final stored = await metadataRepository.getForAudio(audioPath);
  final metadata =
      stored ??
      LocalMediaMetadata(sourcePath: audioPath, updatedAt: DateTime.now());
  await metadataRepository.save(
    metadata.copyWith(
      updatedAt: DateTime.now(),
      metadata: {
        ...metadata.metadata,
        'linkedProjectId': projectId,
        'hasLyrics': true,
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
