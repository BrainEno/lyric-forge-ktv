import 'dart:io';

import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../models/local_media_metadata.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'playback_session_service.dart';

/// Resolves the lyric project backing a playback item.
///
/// Resolution order:
/// 1. the item's explicit [PlaybackItem.projectId];
/// 2. the persisted `linkedProjectId` in optional local media metadata;
/// 3. any local project whose audio asset matches the item's audio path.
///
/// When the persisted link is stale it is repaired, or cleared once nothing
/// matches, so one playback session heals the association instead of repeating
/// the same broken result. Optional metadata failures are swallowed: lyric
/// resolution must never depend on a writable metadata store.
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

  final audioPath = item.audioAsset.originalPath;
  final metadata = await _metadataFor(metadataRepository, audioPath);
  final linkedProjectId = _linkedProjectIdOf(metadata);

  if (linkedProjectId != null) {
    final linked = await _projectFor(projectRepository, linkedProjectId);
    if (linked != null && linked.hasLyrics) {
      return linked.id;
    }
  }

  final matchedProjectId = await _scannedProjectIdForAudio(
    projectRepository,
    audioPath,
  );
  if (matchedProjectId != null && matchedProjectId == linkedProjectId) {
    // The scan rediscovered the same id; rewriting an identical link would
    // only refresh timestamps, so keep resolution read-only here.
    return matchedProjectId;
  }

  await _healLink(
    metadataRepository: metadataRepository,
    metadata: metadata,
    audioPath: audioPath,
    linkedProjectId: linkedProjectId,
    matchedProjectId: matchedProjectId,
  );
  return matchedProjectId;
}

String? _linkedProjectIdOf(LocalMediaMetadata? metadata) {
  final rawProjectId = metadata?.metadata['linkedProjectId'];
  if (rawProjectId is! String || rawProjectId.trim().isEmpty) return null;
  return rawProjectId.trim();
}

Future<LocalMediaMetadata?> _metadataFor(
  LocalMediaMetadataRepository repository,
  String audioPath,
) async {
  try {
    return await repository.getForAudio(audioPath);
  } catch (_) {
    // Optional media metadata must never prevent lyric resolution.
    return null;
  }
}

Future<ProjectManifest?> _projectFor(
  ProjectRepository repository,
  String projectId,
) async {
  try {
    return await repository.getProjectById(projectId);
  } catch (_) {
    return null;
  }
}

Future<String?> _scannedProjectIdForAudio(
  ProjectRepository repository,
  String path,
) async {
  try {
    final projects = await repository.getAllProjects();
    for (final project in projects) {
      final projectPath = project.audioAsset?.originalPath;
      if (projectPath == null || projectPath.trim().isEmpty) continue;
      if (!project.hasLyrics) continue;
      if (_sameAudioPath(projectPath, path)) return project.id;
    }
  } catch (_) {
    // Project scanning is a best-effort fallback.
  }
  return null;
}

Future<void> _healLink({
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
      return;
    }
    if (linkedProjectId != null && metadata != null) {
      final cleared = {...metadata.metadata}
        ..remove('linkedProjectId')
        ..remove('hasLyrics');
      await metadataRepository.save(
        metadata.copyWith(updatedAt: DateTime.now(), metadata: cleared),
      );
    }
  } catch (_) {
    // Self-healing is best effort; a failed write keeps resolution alive.
  }
}

bool _sameAudioPath(String a, String b) {
  final left = File(a).absolute.path;
  final right = File(b).absolute.path;
  if (Platform.isWindows) return left.toLowerCase() == right.toLowerCase();
  return left == right;
}
