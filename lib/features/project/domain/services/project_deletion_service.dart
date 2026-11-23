import '../models/project_manifest.dart';

/// What deleting a project would do, and whether it may happen now (D-063).
class ProjectDeletionCheck {
  const ProjectDeletionCheck({
    this.blocker,
    this.removableBytes = 0,
    this.recordings = 0,
    this.hasFiles = false,
  });

  /// Why the project cannot be deleted right now, for the user; null when
  /// it can.
  final String? blocker;

  /// Whether the project has a working folder the app created (recognition
  /// files, separated tracks, KTV recordings) that can go with it.
  final bool hasFiles;

  /// Size of that folder.
  final int removableBytes;

  /// KTV recordings in that folder.
  final int recordings;

  bool get canDelete => blocker == null;
}

/// How a deletion went.
class ProjectDeletionResult {
  const ProjectDeletionResult({this.removedFiles = false, this.fileError});

  /// Whether the project's working folder was removed too.
  final bool removedFiles;

  /// Why removing the folder failed; the project itself is gone regardless.
  final String? fileError;
}

/// A deletion refused because the project is in use.
class ProjectDeletionBlockedException implements Exception {
  const ProjectDeletionBlockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Deletes lyric projects and what only they use.
///
/// The song's own audio file is never touched. Library songs linked to a
/// deleted project find another project for the same file, or show no
/// lyrics, the next time they are played (the playback resolver heals stale
/// links).
abstract class ProjectDeletionService {
  Future<ProjectDeletionCheck> check(ProjectManifest project);

  /// Deletes [project]; with [removeFiles] also its working folder.
  ///
  /// Throws [ProjectDeletionBlockedException] when the project is being
  /// recognised or played.
  Future<ProjectDeletionResult> delete(
    ProjectManifest project, {
    bool removeFiles = true,
  });
}
