import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../transcription/domain/models/transcription_queue_models.dart';
import '../../../transcription/domain/services/batch_transcription_queue.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';
import '../../domain/services/project_deletion_service.dart';

/// Deletes projects from the local store and their app-created folder
/// (D-063).
///
/// The folder is `<support>/LyricForge/Projects/<id>`: recognition files,
/// separated tracks and KTV recordings. A project that names its own
/// [ProjectManifest.projectDirectory] keeps that folder, since the user may
/// have chosen it, and so does a folder another project's audio lives in.
class LocalProjectDeletionService implements ProjectDeletionService {
  LocalProjectDeletionService({
    required this.projectRepository,
    this.playbackSession,
    this.transcriptionQueue,
    Future<Directory> Function()? projectsRoot,
  }) : _projectsRoot = projectsRoot ?? _defaultProjectsRoot;

  final ProjectRepository projectRepository;
  final PlaybackSessionService? playbackSession;
  final BatchTranscriptionQueue? transcriptionQueue;
  final Future<Directory> Function() _projectsRoot;

  static Future<Directory> _defaultProjectsRoot() async {
    final support = await getApplicationSupportDirectory();
    final separator = Platform.pathSeparator;
    return Directory(
      '${support.path}${separator}LyricForge${separator}Projects',
    );
  }

  /// Why [project] cannot go now, or null.
  String? blockerOf(ProjectManifest project) {
    final queue = transcriptionQueue?.current.items ?? const [];
    final recognising = queue.any(
      (item) =>
          item.projectId == project.id &&
          item.status == TranscriptionQueueItemStatus.running,
    );
    if (recognising) return '这首歌正在批量识别，先暂停识别队列再删除';
    final playing = playbackSession?.currentState.currentItem?.projectId;
    if (playing == project.id) return '这首歌正在播放，换一首或停止播放后再删除';
    return null;
  }

  /// The working folder that would be removed with [project], or null.
  Future<Directory?> removableFolder(ProjectManifest project) async {
    final explicit = project.projectDirectory?.trim() ?? '';
    if (explicit.isNotEmpty) return null;
    if (project.id.isEmpty ||
        project.id.contains('/') ||
        project.id.contains(r'\') ||
        project.id.contains('..')) {
      return null;
    }
    final root = await _projectsRoot();
    final folder = Directory(
      '${root.path}${Platform.pathSeparator}${project.id}',
    );
    if (!await folder.exists()) return null;
    final inside = '${_comparable(folder.absolute.path)}/';
    final others = await projectRepository.getAllProjects();
    for (final other in others) {
      if (other.id == project.id) continue;
      final audio = other.audioAsset;
      if (audio == null) continue;
      for (final path in [
        audio.originalPath,
        audio.normalizedPath,
        audio.vocalPath,
        audio.instrumentalPath,
      ]) {
        if (path == null || path.isEmpty) continue;
        if (_comparable(File(path).absolute.path).startsWith(inside)) {
          return null;
        }
      }
    }
    return folder;
  }

  static String _comparable(String path) {
    final slashed = path.replaceAll(r'\', '/');
    return Platform.isWindows || Platform.isMacOS
        ? slashed.toLowerCase()
        : slashed;
  }

  @override
  Future<ProjectDeletionCheck> check(ProjectManifest project) async {
    final blocker = blockerOf(project);
    final folder = await removableFolder(project);
    if (folder == null) return ProjectDeletionCheck(blocker: blocker);
    var bytes = 0;
    var recordings = 0;
    try {
      await for (final entity in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) bytes += await entity.length();
      }
      final takes = Directory(
        '${folder.path}${Platform.pathSeparator}recordings',
      );
      if (await takes.exists()) {
        recordings = await takes.list().where((e) => e is Directory).length;
      }
    } on FileSystemException catch (error) {
      appLog.warning('project', 'Could not measure project folder: $error');
    }
    return ProjectDeletionCheck(
      blocker: blocker,
      hasFiles: true,
      removableBytes: bytes,
      recordings: recordings,
    );
  }

  @override
  Future<ProjectDeletionResult> delete(
    ProjectManifest project, {
    bool removeFiles = true,
  }) async {
    final blocker = blockerOf(project);
    if (blocker != null) throw ProjectDeletionBlockedException(blocker);
    final folder = removeFiles ? await removableFolder(project) : null;

    await projectRepository.deleteProject(project.id);
    await _forgetQueueItems(project.id);

    if (folder == null) return const ProjectDeletionResult();
    try {
      await folder.delete(recursive: true);
      return const ProjectDeletionResult(removedFiles: true);
    } on FileSystemException catch (error) {
      appLog.warning(
        'project',
        'Deleted project ${project.id} but not its folder',
        error: error,
      );
      return ProjectDeletionResult(fileError: error.message);
    }
  }

  /// Takes the project's finished or failed entries off the recognition
  /// queue, so they neither open a missing project nor make it again on a
  /// retry.
  Future<void> _forgetQueueItems(String projectId) async {
    final queue = transcriptionQueue;
    if (queue == null) return;
    final items = queue.current.items.where(
      (item) =>
          item.projectId == projectId &&
          item.status != TranscriptionQueueItemStatus.running,
    );
    for (final item in items.toList()) {
      try {
        await queue.remove(item.id);
      } on Object catch (error, stackTrace) {
        appLog.warning(
          'project',
          'Could not remove queue item ${item.id} of a deleted project',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
