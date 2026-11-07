import '../../../project/domain/repositories/project_repository.dart';
import '../models/local_media_metadata.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'audio_path_canonicalizer.dart';
import 'playback_session_service.dart';

/// Structured outcome of resolving the lyric project for one playback item.
///
/// Playback surfaces must agree on whether a song has lyrics, so the resolver
/// reports the resolved project, whether it actually carries lyrics, and
/// whether the persisted link was rewritten or cleared along the way.
class PlaybackLyricsResolution {
  const PlaybackLyricsResolution({
    this.projectId,
    this.hasLyrics = false,
    this.repairedLink = false,
    this.clearedLink = false,
  });

  /// Project that backs the item's lyrics, if any.
  final String? projectId;

  /// Whether [projectId] resolves to a project that contains a lyric document.
  final bool hasLyrics;

  /// A stale persisted link was rewritten to point at [projectId].
  final bool repairedLink;

  /// A persisted link was removed because no lyric project matched the audio.
  final bool clearedLink;

  bool get hasProject => projectId != null;

  static const empty = PlaybackLyricsResolution();
}

/// Resolves the lyric project backing a playback item.
///
/// Resolution order:
/// 1. the item's explicit [PlaybackItem.projectId];
/// 2. the persisted `linkedProjectId` in optional local media metadata;
/// 3. any local project whose audio asset matches the item's audio path.
///
/// Resolution is independent of the cached `hasLyrics` flag: a song enqueued
/// before its lyric project existed must still discover that project. Stale
/// links are repaired, or cleared once nothing matches, so one playback session
/// heals the association instead of repeating the same broken result. Optional
/// metadata write failures are swallowed. Read failures are not treated as
/// missing projects: callers must not clear links or update cached flags based
/// on an incomplete lookup.
Future<PlaybackLyricsResolution> resolvePlaybackLyrics({
  required PlaybackItem item,
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository metadataRepository,
  required AudioPathCanonicalizer pathCanonicalizer,
}) async {
  final directProjectId = item.projectId?.trim();
  if (directProjectId != null && directProjectId.isNotEmpty) {
    final project = await projectRepository.getProjectById(directProjectId);
    return PlaybackLyricsResolution(
      projectId: project?.id,
      hasLyrics: project?.hasLyrics ?? false,
    );
  }
  if (item.isRemoteStream) return PlaybackLyricsResolution.empty;

  final audioPath = item.audioAsset.originalPath;
  final metadata = await readCompleteLocalMediaMetadataForAudio(
    metadataRepository,
    audioPath,
  );
  final linkedProjectId = _linkedProjectIdOf(metadata);

  if (linkedProjectId != null) {
    final linked = await projectRepository.getProjectById(linkedProjectId);
    if (linked != null && linked.hasLyrics) {
      return PlaybackLyricsResolution(projectId: linked.id, hasLyrics: true);
    }
  }

  final matchedProjectId = await _scannedProjectIdForAudio(
    projectRepository,
    audioPath,
    pathCanonicalizer,
  );
  if (matchedProjectId != null && matchedProjectId == linkedProjectId) {
    // The scan rediscovered the same id; rewriting an identical link would
    // only refresh timestamps, so keep resolution read-only here.
    return PlaybackLyricsResolution(
      projectId: matchedProjectId,
      hasLyrics: true,
    );
  }

  final healing = await _healLink(
    metadataRepository: metadataRepository,
    metadata: metadata,
    audioPath: audioPath,
    linkedProjectId: linkedProjectId,
    matchedProjectId: matchedProjectId,
  );
  return PlaybackLyricsResolution(
    projectId: matchedProjectId,
    hasLyrics: matchedProjectId != null,
    repairedLink: healing == _LinkHealing.repaired,
    clearedLink: healing == _LinkHealing.cleared,
  );
}

/// Project-only view used by surfaces that just need the editor target.
Future<String?> resolvePlaybackLyricsProjectId({
  required PlaybackItem item,
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository metadataRepository,
  required AudioPathCanonicalizer pathCanonicalizer,
}) async {
  final resolution = await resolvePlaybackLyrics(
    item: item,
    projectRepository: projectRepository,
    metadataRepository: metadataRepository,
    pathCanonicalizer: pathCanonicalizer,
  );
  return resolution.projectId;
}

String? _linkedProjectIdOf(LocalMediaMetadata? metadata) {
  final rawProjectId = metadata?.metadata['linkedProjectId'];
  if (rawProjectId is! String || rawProjectId.trim().isEmpty) return null;
  return rawProjectId.trim();
}

Future<String?> _scannedProjectIdForAudio(
  ProjectRepository repository,
  String path,
  AudioPathCanonicalizer pathCanonicalizer,
) async {
  final canonicalPath = pathCanonicalizer.canonicalize(path);
  final projects = await repository.getAllProjects();
  for (final project in projects) {
    final projectPath = project.audioAsset?.originalPath;
    if (projectPath == null || projectPath.trim().isEmpty) continue;
    if (!project.hasLyrics) continue;
    if (pathCanonicalizer.canonicalize(projectPath) == canonicalPath) {
      return project.id;
    }
  }
  return null;
}

enum _LinkHealing { none, repaired, cleared }

Future<_LinkHealing> _healLink({
  required LocalMediaMetadataRepository metadataRepository,
  required LocalMediaMetadata? metadata,
  required String audioPath,
  required String? linkedProjectId,
  required String? matchedProjectId,
}) async {
  try {
    if (matchedProjectId != null) {
      final healed =
          metadata ??
          LocalMediaMetadata(sourcePath: audioPath, updatedAt: DateTime.now());
      await metadataRepository.save(
        healed.copyWith(
          updatedAt: DateTime.now(),
          metadata: {
            ...healed.metadata,
            'linkedProjectId': matchedProjectId,
            'hasLyrics': true,
          },
        ),
      );
      return _LinkHealing.repaired;
    }
    if (linkedProjectId != null && metadata != null) {
      final cleared = {...metadata.metadata}
        ..remove('linkedProjectId')
        ..remove('hasLyrics');
      await metadataRepository.save(
        metadata.copyWith(updatedAt: DateTime.now(), metadata: cleared),
      );
      return _LinkHealing.cleared;
    }
  } catch (_) {
    // Self-healing is best effort; a failed write keeps resolution alive.
  }
  return _LinkHealing.none;
}
