import '../../../project/domain/repositories/project_repository.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'playback_session_service.dart';

/// Resolves the lyric project backing a playback item.
///
/// Project queue items carry [PlaybackItem.projectId] directly. Local-library
/// items keep their relationship in user metadata as `linkedProjectId`.
Future<String?> resolvePlaybackLyricsProjectId({
  required PlaybackItem item,
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository metadataRepository,
}) async {
  final directProjectId = item.projectId?.trim();
  if (directProjectId != null && directProjectId.isNotEmpty) {
    final project = await projectRepository.getProjectById(directProjectId);
    return project?.id;
  }

  if (item.isRemoteStream || !item.hasLyrics) return null;

  final metadata = await metadataRepository.getForAudio(
    item.audioAsset.originalPath,
  );
  final rawProjectId = metadata?.metadata['linkedProjectId'];
  if (rawProjectId is! String || rawProjectId.trim().isEmpty) return null;

  final project = await projectRepository.getProjectById(rawProjectId.trim());
  if (project == null || !project.hasLyrics) return null;
  return project.id;
}
