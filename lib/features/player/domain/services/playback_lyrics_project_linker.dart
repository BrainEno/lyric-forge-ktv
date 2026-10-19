import 'dart:io';

import '../models/local_media_metadata.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'playback_session_service.dart';

Future<void> linkPlaybackLyricsProject({
  required String audioPath,
  required String projectId,
  required LocalMediaMetadataRepository metadataRepository,
  required PlaybackSessionService playbackSession,
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

  final normalizedAudioPath = _normalizedPath(audioPath);
  for (final item in playbackSession.currentState.queue) {
    if (item.isRemoteStream ||
        _normalizedPath(item.audioAsset.originalPath) != normalizedAudioPath ||
        item.hasLyrics) {
      continue;
    }
    await playbackSession.updateItem(item.copyWith(hasLyrics: true));
  }
}

String _normalizedPath(String path) {
  final absolutePath = File(path).absolute.path;
  return Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
}
