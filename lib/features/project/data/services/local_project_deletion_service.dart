import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../transcription/domain/models/transcription_queue_models.dart';
import '../../../transcription/domain/services/batch_transcription_queue.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';
import '../../domain/services/project_deletion_service.dart';

/// Deletes projects into 最近删除 on disk (D-063, D-064).
///
/// A project's working folder is `<support>/LyricForge/Projects/<id>`:
/// recognition files, separated tracks and KTV recordings. A project that
/// names its own [ProjectManifest.projectDirectory] keeps that folder, since
/// the user may have chosen it, and so does a folder another project's audio
/// lives in.
///
/// 最近删除 is `<support>/LyricForge/Trash/Projects/<id>/`: `entry.json`
/// holds the project record and when it was deleted, `files/` the moved
/// working folder. The record is written there before the project leaves
/// the store, so a failure halfway loses nothing.
class LocalProjectDeletionService implements ProjectDeletionService {
  LocalProjectDeletionService({
    required this.projectRepository,
    ProjectRecordRestorer? restorer,
    this.playbackSession,
    this.transcriptionQueue,
    Future<Directory> Function()? projectsRoot,
    Future<Directory> Function()? trashRoot,
    DateTime Function()? now,
  }) : _restorer =
           restorer ??
           (projectRepository is ProjectRecordRestorer
               ? projectRepository as ProjectRecordRestorer
               : null),
       _projectsRoot = projectsRoot ?? _defaultProjectsRoot,
       _trashRoot = trashRoot ?? _defaultTrashRoot,
       _now = now ?? DateTime.now;

  final ProjectRepository projectRepository;
  final PlaybackSessionService? playbackSession;
  final BatchTranscriptionQueue? transcriptionQueue;
  final ProjectRecordRestorer? _restorer;
  final Future<Directory> Function() _projectsRoot;
  final Future<Directory> Function() _trashRoot;
  final DateTime Function() _now;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const _entryFile = 'entry.json';
  static const _filesFolder = 'files';
  static const _entryVersion = 1;

  static String get _sep => Platform.pathSeparator;

  static Future<Directory> _lyricForgeFolder(String name) async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${_sep}LyricForge$_sep$name');
  }

  static Future<Directory> _defaultProjectsRoot() =>
      _lyricForgeFolder('Projects');

  static Future<Directory> _defaultTrashRoot() async {
    final trash = await _lyricForgeFolder('Trash');
    return Directory('${trash.path}${_sep}Projects');
  }

  @override
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
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

  static bool _safeId(String id) =>
      id.isNotEmpty &&
      !id.contains('/') &&
      !id.contains(r'\') &&
      !id.contains('..');

  Future<Directory> _workingFolderOf(String id) async {
    final root = await _projectsRoot();
    return Directory('${root.path}$_sep$id');
  }

  Future<Directory> _entryOf(String id) async {
    final root = await _trashRoot();
    return Directory('${root.path}$_sep$id');
  }

  /// The working folder that goes with [project], or null.
  Future<Directory?> removableFolder(ProjectManifest project) async {
    final explicit = project.projectDirectory?.trim() ?? '';
    if (explicit.isNotEmpty) return null;
    if (!_safeId(project.id)) return null;
    final folder = await _workingFolderOf(project.id);
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

  static Future<int> _sizeOf(Directory folder) async {
    var bytes = 0;
    try {
      await for (final entity in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) bytes += await entity.length();
      }
    } on FileSystemException catch (error) {
      appLog.warning('project', 'Could not measure project folder: $error');
    }
    return bytes;
  }

  @override
  Future<ProjectDeletionCheck> check(ProjectManifest project) async {
    final blocker = blockerOf(project);
    final folder = await removableFolder(project);
    if (folder == null) return ProjectDeletionCheck(blocker: blocker);
    final bytes = await _sizeOf(folder);
    var recordings = 0;
    try {
      final takes = Directory('${folder.path}${_sep}recordings');
      if (await takes.exists()) {
        recordings = await takes.list().where((e) => e is Directory).length;
      }
    } on FileSystemException catch (error) {
      appLog.warning('project', 'Could not count KTV recordings: $error');
    }
    return ProjectDeletionCheck(
      blocker: blocker,
      hasFiles: true,
      removableBytes: bytes,
      recordings: recordings,
    );
  }

  @override
  Future<ProjectDeletionResult> delete(ProjectManifest project) async {
    final blocker = blockerOf(project);
    if (blocker != null) throw ProjectDeletionBlockedException(blocker);
    if (!_safeId(project.id)) {
      // Not a folder name: nothing could be kept, so it cannot be undone.
      await projectRepository.deleteProject(project.id);
      await _forgetQueueItems(project.id);
      _changed();
      return const ProjectDeletionResult();
    }
    final current = await projectRepository.getProjectById(project.id);
    final record = current ?? project;
    final folder = await removableFolder(record);

    final entry = await _entryOf(project.id);
    if (await entry.exists()) await entry.delete(recursive: true);
    await entry.create(recursive: true);
    final bytes = folder == null ? 0 : await _sizeOf(folder);
    await _writeEntry(entry, record, hasFiles: folder != null, bytes: bytes);

    try {
      await projectRepository.deleteProject(project.id);
    } on Object {
      await _quietlyDelete(entry);
      rethrow;
    }
    await _forgetQueueItems(project.id);

    var result = const ProjectDeletionResult();
    if (folder != null) {
      try {
        await folder.rename('${entry.path}$_sep$_filesFolder');
        result = const ProjectDeletionResult(movedFiles: true);
      } on FileSystemException catch (error) {
        appLog.warning(
          'project',
          'Moved project ${project.id} to the trash but not its folder',
          error: error,
        );
        await _writeEntry(entry, record, hasFiles: false, bytes: 0);
        result = ProjectDeletionResult(fileError: error.message);
      }
    }
    _changed();
    return result;
  }

  Future<void> _writeEntry(
    Directory entry,
    ProjectManifest project, {
    required bool hasFiles,
    required int bytes,
  }) async {
    final file = File('${entry.path}$_sep$_entryFile');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': _entryVersion,
        'deletedAt': _now().toUtc().toIso8601String(),
        'hasFiles': hasFiles,
        'bytes': bytes,
        'project': project.toJson(),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<TrashedProject?> _readEntry(Directory entry) async {
    final file = File('${entry.path}$_sep$_entryFile');
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final project = json['project'];
      final deletedAt = DateTime.tryParse('${json['deletedAt']}');
      if (project is! Map<String, dynamic> || deletedAt == null) return null;
      return TrashedProject(
        project: ProjectManifest.fromJson(project),
        deletedAt: deletedAt.toLocal(),
        hasFiles:
            json['hasFiles'] == true &&
            await Directory('${entry.path}$_sep$_filesFolder').exists(),
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
    } on Object catch (error, stackTrace) {
      appLog.warning(
        'project',
        'Unreadable trash entry ${entry.path}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _quietlyDelete(Directory folder) async {
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } on FileSystemException catch (error) {
      appLog.warning(
        'project',
        'Could not delete ${folder.path}',
        error: error,
      );
    }
  }

  @override
  Future<List<TrashedProject>> trashed() async {
    final root = await _trashRoot();
    if (!await root.exists()) return const [];
    final now = _now();
    final entries = <TrashedProject>[];
    var purged = false;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final entry = await _readEntry(entity);
      if (entry == null) continue;
      if (entry.daysLeft(now) == 0) {
        await _quietlyDelete(entity);
        purged = true;
        continue;
      }
      entries.add(entry);
    }
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    if (purged) _changed();
    return entries;
  }

  @override
  Future<ProjectManifest> restore(String id) async {
    if (!_safeId(id)) throw const ProjectRestoreException('找不到这个工程');
    final restorer = _restorer;
    if (restorer == null) {
      throw const ProjectRestoreException('这里不能恢复工程');
    }
    final entry = await _entryOf(id);
    final trashed = await _readEntry(entry);
    if (trashed == null) {
      throw const ProjectRestoreException('“最近删除”里已经没有这个工程');
    }
    if (await projectRepository.getProjectById(id) != null) {
      throw const ProjectRestoreException('这个工程已经在工程列表里');
    }
    final files = Directory('${entry.path}$_sep$_filesFolder');
    final target = await _workingFolderOf(id);
    final moveFiles = await files.exists();
    if (moveFiles && await target.exists()) {
      throw const ProjectRestoreException('工程文件夹已被占用，没法恢复');
    }

    final restored = await restorer.restoreProject(trashed.project);
    if (moveFiles) {
      try {
        await target.parent.create(recursive: true);
        await files.rename(target.path);
      } on FileSystemException catch (error) {
        // The record is back; keep the folder in the trash rather than lose
        // it, and say so in the log.
        appLog.warning(
          'project',
          'Restored project $id but not its folder',
          error: error,
        );
        _changed();
        return restored;
      }
    }
    await _quietlyDelete(entry);
    _changed();
    return restored;
  }

  @override
  Future<void> purge(String id) async {
    if (!_safeId(id)) return;
    await _quietlyDelete(await _entryOf(id));
    _changed();
  }

  @override
  Future<int> purgeAll() async {
    final root = await _trashRoot();
    if (!await root.exists()) return 0;
    var count = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      await _quietlyDelete(entity);
      count++;
    }
    _changed();
    return count;
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
