import 'dart:async';

import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_deletion_service.dart';

/// An in-memory 最近删除 (D-064) for widget tests.
///
/// [removeProject] and [addProject] keep the test's project store in step
/// with deleting and restoring.
class FakeProjectDeletionService implements ProjectDeletionService {
  FakeProjectDeletionService({
    this.removeProject,
    this.addProject,
    DateTime Function()? now,
  }) : now = now ?? (() => DateTime(2026, 12, 1));

  final Future<void> Function(String id)? removeProject;
  final Future<void> Function(ProjectManifest project)? addProject;
  final DateTime Function() now;

  final deleted = <String>[];
  final restored = <String>[];
  final purged = <String>[];
  final blockers = <String, String>{};
  final trash = <TrashedProject>[];
  int folderBytes = 5 * 1024 * 1024;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<ProjectDeletionCheck> check(ProjectManifest project) async =>
      ProjectDeletionCheck(
        blocker: blockers[project.id],
        hasFiles: true,
        removableBytes: folderBytes,
      );

  @override
  Future<ProjectDeletionResult> delete(ProjectManifest project) async {
    final blocker = blockers[project.id];
    if (blocker != null) throw ProjectDeletionBlockedException(blocker);
    deleted.add(project.id);
    await removeProject?.call(project.id);
    trash.insert(
      0,
      TrashedProject(
        project: project,
        deletedAt: now(),
        hasFiles: true,
        bytes: folderBytes,
      ),
    );
    _changes.add(null);
    return const ProjectDeletionResult(movedFiles: true);
  }

  @override
  Future<List<TrashedProject>> trashed() async => List.of(trash);

  @override
  Future<ProjectManifest> restore(String id) async {
    final index = trash.indexWhere((entry) => entry.id == id);
    if (index < 0) throw const ProjectRestoreException('“最近删除”里已经没有这个工程');
    final entry = trash.removeAt(index);
    restored.add(id);
    await addProject?.call(entry.project);
    _changes.add(null);
    return entry.project;
  }

  @override
  Future<void> purge(String id) async {
    trash.removeWhere((entry) => entry.id == id);
    purged.add(id);
    _changes.add(null);
  }

  @override
  Future<int> purgeAll() async {
    final count = trash.length;
    purged.addAll(trash.map((entry) => entry.id));
    trash.clear();
    _changes.add(null);
    return count;
  }
}
