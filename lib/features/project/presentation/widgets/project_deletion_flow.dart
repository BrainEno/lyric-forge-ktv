import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/services/project_deletion_service.dart';
import 'project_delete_dialog.dart';

/// The outcome of [deleteProjectsWithConfirmation].
class ProjectDeletionOutcome {
  const ProjectDeletionOutcome({
    this.deleted = const [],
    this.blocked = const [],
    this.failed = 0,
    this.fileErrors = 0,
  });

  /// Ids of the projects that are gone.
  final List<String> deleted;

  /// Projects left alone because they are in use, with the reason.
  final List<({ProjectManifest project, String reason})> blocked;
  final int failed;

  /// Deleted projects whose working folder could not be removed.
  final int fileErrors;

  bool get cancelled => deleted.isEmpty && blocked.isEmpty && failed == 0;

  /// One line for a snackbar, or null when nothing happened.
  String? get message {
    if (cancelled) return null;
    final parts = <String>[
      if (deleted.isNotEmpty)
        deleted.length == 1 ? '工程已删除' : '已删除 ${deleted.length} 个工程',
      if (blocked.length == 1 && deleted.isEmpty) blocked.single.reason,
      if (blocked.isNotEmpty && (blocked.length > 1 || deleted.isNotEmpty))
        '${blocked.length} 个正在使用，没有删除',
      if (failed > 0) '$failed 个删除失败',
      if (fileErrors > 0) '$fileErrors 个工程文件夹没能删除，可稍后手动清理',
    ];
    return parts.join('；');
  }
}

/// Checks, confirms and deletes [projects] (D-063), then shows the result
/// in a snackbar. Projects in use are skipped and named.
Future<ProjectDeletionOutcome> deleteProjectsWithConfirmation(
  BuildContext context, {
  required ProjectDeletionService service,
  required List<ProjectManifest> projects,
  String? keepNote,
}) async {
  if (projects.isEmpty) return const ProjectDeletionOutcome();
  final messenger = ScaffoldMessenger.of(context);
  final checks = [for (final project in projects) await service.check(project)];
  final blocked = [
    for (var index = 0; index < projects.length; index++)
      if (checks[index].blocker case final reason?)
        (project: projects[index], reason: reason),
  ];
  final deletable = [
    for (var index = 0; index < projects.length; index++)
      if (checks[index].canDelete) index,
  ];
  if (deletable.isEmpty) {
    final outcome = ProjectDeletionOutcome(blocked: blocked);
    messenger.showSnackBar(SnackBar(content: Text(outcome.message!)));
    return outcome;
  }
  if (!context.mounted) return const ProjectDeletionOutcome();

  final removeFiles = await confirmProjectDeletion(
    context,
    projects: [for (final index in deletable) projects[index]],
    checks: [for (final index in deletable) checks[index]],
    keepNote: keepNote,
  );
  if (removeFiles == null) return const ProjectDeletionOutcome();

  final deleted = <String>[];
  var failed = 0;
  var fileErrors = 0;
  final skipped = [...blocked];
  for (final index in deletable) {
    final project = projects[index];
    try {
      final result = await service.delete(project, removeFiles: removeFiles);
      deleted.add(project.id);
      if (result.fileError != null) fileErrors++;
    } on ProjectDeletionBlockedException catch (error) {
      skipped.add((project: project, reason: error.message));
    } on Object catch (error, stackTrace) {
      failed++;
      appLog.warning(
        'project',
        'Deleting project ${project.id} failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  final outcome = ProjectDeletionOutcome(
    deleted: deleted,
    blocked: skipped,
    failed: failed,
    fileErrors: fileErrors,
  );
  final message = outcome.message;
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  return outcome;
}
