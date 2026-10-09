import 'dart:convert';
import 'dart:io';

import '../../domain/models/ktv_recording_session.dart';

/// Discovers existing takes without mutating their original audio or manifests.
class KtvTakeHistoryStore {
  const KtvTakeHistoryStore();

  Future<List<KtvRecordingSession>> listFromDirectory(
    Directory projectDirectory,
    String projectId,
  ) async {
    final root = Directory('${projectDirectory.path}${Platform.pathSeparator}recordings');
    if (!await root.exists()) return const [];
    final takes = <KtvRecordingSession>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !entity.path.split(Platform.pathSeparator).last.startsWith('take_')) {
        continue;
      }
      final manifest = File('${entity.path}${Platform.pathSeparator}session.json');
      if (!await manifest.exists()) continue;
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final take = KtvRecordingSession.fromJson(decoded);
        if (take.projectId != projectId || take.completedAt == null) continue;
        // Never trust paths in a manifest when listing a project's recordings.
        if (!_samePath(File(take.manifestPath).absolute.path, manifest.absolute.path) ||
            !_samePath(File(take.micStemPath).absolute.path,
                File('${entity.path}${Platform.pathSeparator}voice.wav').absolute.path) ||
            await File(take.micStemPath).stat().then((stat) => stat.type != FileSystemEntityType.file) ||
            await File(take.micStemPath).exists() == false) continue;
        takes.add(take);
      } catch (_) {
        // One corrupt or interrupted take must not hide the remaining history.
      }
    }
    takes.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(takes);
  }

  /// Deletes only a complete take folder beneath the given project's recordings.
  /// The user interface must obtain explicit confirmation before calling this.
  Future<void> deleteTake(
    Directory projectDirectory,
    String projectId,
    KtvRecordingSession take,
  ) async {
    if (take.projectId != projectId) {
      throw const FileSystemException('录音不属于当前工程');
    }
    final recordings = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}recordings',
    );
    final folder = Directory(
      '${recordings.path}${Platform.pathSeparator}${take.id}',
    );
    if (!take.id.startsWith('take_') ||
        take.id.contains('/') ||
        take.id.contains(Platform.pathSeparator) ||
        take.id == 'take_..' ||
        await FileSystemEntity.type(folder.path, followLinks: false) != FileSystemEntityType.directory ||
        !_inside(folder, File(take.manifestPath)) ||
        !_inside(folder, File(take.micStemPath))) {
      throw const FileSystemException('录音路径不安全，已取消删除');
    }
    // Re-read the index so a stale UI entry cannot delete an unrelated folder.
    final indexed = await listFromDirectory(projectDirectory, projectId);
    if (!indexed.any((entry) =>
        entry.id == take.id && entry.manifestPath == take.manifestPath)) {
      throw const FileSystemException('录音不存在或已发生变化');
    }
    // Refuse symlinked files and nested directories: recursive deletion must
    // never follow untrusted take contents or remove unrelated user files.
    await for (final child in folder.list(recursive: true, followLinks: false)) {
      if (child is Link) {
        throw const FileSystemException('录音包含符号链接，已取消删除');
      }
    }
    await folder.delete(recursive: true);
  }

  bool _samePath(String left, String right) =>
      Platform.isWindows ? left.toLowerCase() == right.toLowerCase() : left == right;

  bool _inside(Directory directory, File file) {
    final root = directory.absolute.path;
    final path = file.absolute.path;
    return path.startsWith('$root${Platform.pathSeparator}');
  }
}
