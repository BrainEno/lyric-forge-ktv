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
  /// files, separated tracks, KTV recordings) that goes with it.
  final bool hasFiles;

  /// Size of that folder.
  final int removableBytes;

  /// KTV recordings in that folder.
  final int recordings;

  bool get canDelete => blocker == null;
}

/// How a deletion went.
class ProjectDeletionResult {
  const ProjectDeletionResult({this.movedFiles = false, this.fileError});

  /// Whether the project's working folder went to 最近删除 with it.
  final bool movedFiles;

  /// Why moving the folder failed; the project itself is in 最近删除
  /// regardless, and its folder stays where it was.
  final String? fileError;
}

/// A deletion refused because the project is in use.
class ProjectDeletionBlockedException implements Exception {
  const ProjectDeletionBlockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A project in 最近删除 that could not be put back.
class ProjectRestoreException implements Exception {
  const ProjectRestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A project in 最近删除 (D-064).
class TrashedProject {
  const TrashedProject({
    required this.project,
    required this.deletedAt,
    this.hasFiles = false,
    this.bytes = 0,
  });

  /// The project as it was when it was deleted.
  final ProjectManifest project;
  final DateTime deletedAt;

  /// Whether its working folder is kept with it.
  final bool hasFiles;

  /// Size of that folder.
  final int bytes;

  String get id => project.id;

  /// When it is deleted for good.
  DateTime get expiresAt => deletedAt.add(ProjectDeletionService.retention);

  /// Whole days left before [expiresAt], at least 1 while it is still
  /// there, so the list never says 0 天.
  int daysLeft(DateTime now) {
    final left = expiresAt.difference(now);
    if (left <= Duration.zero) return 0;
    final days = (left.inHours / 24).ceil();
    return days < 1 ? 1 : days;
  }
}

/// Deletes lyric projects into 最近删除, where they can be restored for
/// [retention] (D-063, D-064).
///
/// The song's own audio file is never touched. Library songs linked to a
/// deleted project keep the link, so a restored project is found again; if
/// it is not restored, they find another project for the same file, or show
/// no lyrics, the next time they are played (the playback resolver heals
/// stale links).
abstract class ProjectDeletionService {
  /// How long a deleted project can be restored.
  static const Duration retention = Duration(days: 30);

  /// Fires after a project is deleted, restored or purged, so open lists can
  /// reload — an undo can come from a snackbar after its page has closed.
  Stream<void> get changes;

  Future<ProjectDeletionCheck> check(ProjectManifest project);

  /// Moves [project] and its working folder to 最近删除.
  ///
  /// Throws [ProjectDeletionBlockedException] when the project is being
  /// recognised or played.
  Future<ProjectDeletionResult> delete(ProjectManifest project);

  /// The projects in 最近删除, most recently deleted first. Projects past
  /// [retention] are deleted for good first.
  Future<List<TrashedProject>> trashed();

  /// Puts a deleted project back, with its folder.
  ///
  /// Throws [ProjectRestoreException] when it cannot.
  Future<ProjectManifest> restore(String id);

  /// Deletes a project in 最近删除 for good.
  Future<void> purge(String id);

  /// Empties 最近删除; returns how many projects went.
  Future<int> purgeAll();
}
