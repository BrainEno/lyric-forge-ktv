import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/widgets/undo_snack_bar.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/services/project_deletion_service.dart';
import 'project_delete_dialog.dart';

/// The outcome of [deleteProjectsWithUndo].
class ProjectDeletionOutcome {
  const ProjectDeletionOutcome({
    this.deleted = const [],
    this.blocked = const [],
    this.failed = 0,
    this.fileErrors = 0,
  });

  /// Ids of the projects now in 最近删除.
  final List<String> deleted;

  /// Projects left alone because they are in use, with the reason.
  final List<({ProjectManifest project, String reason})> blocked;
  final int failed;

  /// Deleted projects whose working folder stayed where it was.
  final int fileErrors;

  bool get cancelled => deleted.isEmpty && blocked.isEmpty && failed == 0;

  /// One line for a snackbar, or null when nothing happened.
  String? get message {
    if (cancelled) return null;
    final parts = <String>[
      if (deleted.isNotEmpty)
        deleted.length == 1
            ? '工程已移到“最近删除”'
            : '已删除 ${deleted.length} 个工程，可在“最近删除”恢复',
      if (blocked.length == 1 && deleted.isEmpty) blocked.single.reason,
      if (blocked.isNotEmpty && (blocked.length > 1 || deleted.isNotEmpty))
        '${blocked.length} 个正在使用，没有删除',
      if (failed > 0) '$failed 个删除失败',
      if (fileErrors > 0) '$fileErrors 个工程文件夹没能移走，留在原处',
    ];
    return parts.join('；');
  }
}

/// Puts [ids] back from 最近删除; returns the line for a snackbar.
Future<String> restoreDeletedProjects(
  ProjectDeletionService service,
  List<String> ids,
) async {
  var restored = 0;
  String? problem;
  for (final id in ids) {
    try {
      await service.restore(id);
      restored++;
    } on ProjectRestoreException catch (error) {
      problem ??= error.message;
    } on Object catch (error, stackTrace) {
      problem ??= '恢复失败';
      appLog.warning(
        'project',
        'Restoring project $id failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  if (problem == null) {
    return restored == 1 ? '工程已恢复' : '已恢复 $restored 个工程';
  }
  if (restored == 0) return problem;
  return '已恢复 $restored 个工程；其余：$problem';
}

/// Moves [projects] to 最近删除 (D-063, D-064) and offers 撤销.
///
/// A single project goes at once — the undo is the safety net; several
/// projects, or a [keepNote] explaining a clean-up, are confirmed first.
/// Projects in use are skipped and named.
Future<ProjectDeletionOutcome> deleteProjectsWithUndo(
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
      if (checks[index].canDelete) projects[index],
  ];
  if (deletable.isEmpty) {
    final outcome = ProjectDeletionOutcome(blocked: blocked);
    messenger.showSnackBar(SnackBar(content: Text(outcome.message!)));
    return outcome;
  }
  if (!context.mounted) return const ProjectDeletionOutcome();

  if (projects.length > 1 || keepNote != null) {
    final confirmed = await confirmProjectDeletion(
      context,
      projects: deletable,
      keepNote: keepNote,
    );
    if (!confirmed) return const ProjectDeletionOutcome();
  }

  final deleted = <String>[];
  var failed = 0;
  var fileErrors = 0;
  final skipped = [...blocked];
  for (final project in deletable) {
    try {
      final result = await service.delete(project);
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
  if (message == null) return outcome;
  if (deleted.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } else {
    showUndoSnackBar(
      messenger,
      key: const ValueKey('project_delete_undo'),
      message: message,
      onUndo: () => restoreDeletedProjects(service, deleted),
    );
  }
  return outcome;
}
