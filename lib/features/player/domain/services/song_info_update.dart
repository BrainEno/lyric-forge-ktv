import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../models/local_media_metadata.dart';
import 'playback_session_service.dart';

/// Carries a song's edited 歌曲信息 to everything that shows it (D-059).
///
/// The edit dialog used to relabel one queue item, rebuilt from the copy of
/// the song the screen that opened it had read earlier. Three things went
/// stale:
///
///  * the lyric project kept its old name and artist, so the lyrics player —
///    whose title and online search come from the project — still showed
///    the old (often placeholder) name;
///  * the queue item of that lyric project (`project:<id>`) was not touched;
///  * the relabelled item carried the screen's lyric flag, which could be
///    older than the queue's, so the player bar lost its lyrics.
///
/// This updates the linked project, then every queue item that plays this
/// file or that project, starting from the queue's own copy. A failing
/// project write does not stop the queue update; the result says whether the
/// project was updated.
Future<SongInfoUpdateResult> applySongInfoUpdate({
  required LocalMediaMetadata saved,
  required String fallbackTitle,
  required PlaybackSessionService session,
  ProjectRepository? projectRepository,
  DateTime? now,
}) async {
  final title = saved.resolvedTitle(fallbackTitle);
  final artist = saved.artist?.trim().isNotEmpty == true
      ? saved.artist!.trim()
      : null;
  final linkedProjectId = linkedProjectIdOf(saved);

  var projectUpdated = false;
  Object? projectError;
  if (projectRepository != null && linkedProjectId != null) {
    try {
      final project = await projectRepository.getProjectById(linkedProjectId);
      if (project != null && _needsRename(project, title, artist)) {
        await projectRepository.updateProject(
          renamedProject(project, title: title, artist: artist, now: now),
        );
        projectUpdated = true;
      }
    } on Object catch (error) {
      projectError = error;
    }
  }

  var queueItems = 0;
  for (final item in session.currentState.queue) {
    final playsFile =
        item.projectId == null &&
        !item.isRemoteStream &&
        item.audioAsset.originalPath == saved.sourcePath;
    final playsLinkedLyrics =
        linkedProjectId != null && item.projectId == linkedProjectId;
    if (!playsFile && !playsLinkedLyrics) continue;
    final artwork = saved.resolvedArtwork(item.audioAsset.thumbnailPath);
    await session.updateItem(
      item.copyWith(
        title: title,
        artist: artist,
        clearArtist: artist == null,
        artworkPath: artwork,
        clearArtwork: artwork == null,
        // The queue's flag is the newest; a link on the file only adds.
        hasLyrics: item.hasLyrics || (playsFile && linkedProjectId != null),
      ),
    );
    queueItems++;
  }

  return SongInfoUpdateResult(
    projectUpdated: projectUpdated,
    queueItemsUpdated: queueItems,
    projectError: projectError,
  );
}

/// The lyric project linked to a song, if any.
String? linkedProjectIdOf(LocalMediaMetadata? metadata) {
  final raw = metadata?.metadata['linkedProjectId'];
  if (raw is! String || raw.trim().isEmpty) return null;
  return raw.trim();
}

/// [project] under the song's new [title] and [artist]; a cleared artist
/// clears the project's too.
ProjectManifest renamedProject(
  ProjectManifest project, {
  required String title,
  required String? artist,
  DateTime? now,
}) {
  final renamed = project.copyWith(name: title, updatedAt: now);
  if (artist != null) return renamed.copyWith(artist: artist);
  // copyWith cannot clear a field.
  return ProjectManifest(
    id: renamed.id,
    name: renamed.name,
    album: renamed.album,
    createdAt: renamed.createdAt,
    updatedAt: renamed.updatedAt,
    revision: renamed.revision,
    status: renamed.status,
    currentStage: renamed.currentStage,
    audioAsset: renamed.audioAsset,
    lyricDocument: renamed.lyricDocument,
    projectDirectory: renamed.projectDirectory,
    metadata: renamed.metadata,
  );
}

bool _needsRename(ProjectManifest project, String title, String? artist) =>
    project.name != title || (project.artist?.trim() ?? '') != (artist ?? '');

/// What [applySongInfoUpdate] changed.
class SongInfoUpdateResult {
  const SongInfoUpdateResult({
    required this.projectUpdated,
    required this.queueItemsUpdated,
    this.projectError,
  });

  final bool projectUpdated;
  final int queueItemsUpdated;

  /// Why the linked project could not be renamed, when it could not.
  final Object? projectError;
}
