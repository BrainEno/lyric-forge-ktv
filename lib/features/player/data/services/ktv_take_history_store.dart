import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/ktv_recording_session.dart';
import 'ktv_project_storage.dart';
import 'pcm16_wav_writer.dart';

class KtvTakeHistoryScanResult {
  final List<KtvRecordingSession> takes;
  final int recoveredCount;

  const KtvTakeHistoryScanResult({
    required this.takes,
    required this.recoveredCount,
  });
}

/// Discovers completed takes and safely recovers interrupted local recordings.
class KtvTakeHistoryStore {
  static const int maxDisplayNameLength = 80;

  const KtvTakeHistoryStore();

  Future<KtvTakeHistoryScanResult> scanProject(ProjectManifest project) async {
    final directory = await KtvProjectStorage.resolveProjectDirectory(project);
    return scanFromDirectory(directory, project.id);
  }

  Future<List<KtvRecordingSession>> listProject(ProjectManifest project) async =>
      (await scanProject(project)).takes;

  Future<KtvTakeHistoryScanResult> scanFromDirectory(
    Directory projectDirectory,
    String projectId,
  ) async {
    final root = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}recordings',
    );
    if (!await root.exists()) {
      return const KtvTakeHistoryScanResult(takes: [], recoveredCount: 0);
    }

    final takes = <KtvRecordingSession>[];
    var recoveredCount = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !entity.path.split(Platform.pathSeparator).last.startsWith('take_')) {
        continue;
      }
      final manifest = File(
        '${entity.path}${Platform.pathSeparator}session.json',
      );
      if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        var take = KtvRecordingSession.fromJson(decoded);
        if (take.projectId != projectId) continue;

        final expectedVoice = File(
          '${entity.path}${Platform.pathSeparator}voice.wav',
        );
        // Never trust paths embedded in a manifest before reading or writing.
        if (!_samePath(
              File(take.manifestPath).absolute.path,
              manifest.absolute.path,
            ) ||
            !_samePath(
              File(take.micStemPath).absolute.path,
              expectedVoice.absolute.path,
            ) ||
            await FileSystemEntity.type(
                  take.micStemPath,
                  followLinks: false,
                ) !=
                FileSystemEntityType.file) {
          continue;
        }

        if (take.completedAt == null) {
          final recoveredDuration =
              await Pcm16WavWriter.recoverInterruptedFile(take.micStemPath);
          if (recoveredDuration == null || recoveredDuration <= Duration.zero) {
            continue;
          }
          final recoveryIssue = take.alignmentIssue == null
              ? '录音意外中断，已恢复原始人声；自动混音已停用'
              : '${take.alignmentIssue}；录音随后意外中断，已恢复原始人声';
          take = take.copyWith(
            completedAt: take.startedAt.add(recoveredDuration),
            duration: recoveredDuration,
            alignmentReliable: false,
            alignmentIssue: recoveryIssue,
          );
          await manifest.writeAsString(
            const JsonEncoder.withIndent('  ').convert(take.toJson()),
            flush: true,
          );
          recoveredCount++;
        }
        takes.add(take);
      } catch (_) {
        // One corrupt take must never hide or mutate the remaining history.
      }
    }
    takes.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return b.startedAt.compareTo(a.startedAt);
    });
    return KtvTakeHistoryScanResult(
      takes: List.unmodifiable(takes),
      recoveredCount: recoveredCount,
    );
  }

  Future<List<KtvRecordingSession>> listFromDirectory(
    Directory projectDirectory,
    String projectId,
  ) async =>
      (await scanFromDirectory(projectDirectory, projectId)).takes;

  Future<KtvRecordingSession> updateProjectTakeMetadata(
    ProjectManifest project,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  }) async {
    final directory = await KtvProjectStorage.resolveProjectDirectory(project);
    return updateTakeMetadata(
      directory,
      project.id,
      take,
      displayName: displayName,
      clearDisplayName: clearDisplayName,
      isFavorite: isFavorite,
    );
  }

  Future<KtvRecordingSession> updateTakeMetadata(
    Directory projectDirectory,
    String projectId,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  }) async {
    final normalizedName = displayName?.trim();
    if (normalizedName != null &&
        normalizedName.length > maxDisplayNameLength) {
      throw const FormatException('录音名称不能超过 80 个字符');
    }
    final indexed = await _findIndexedTake(projectDirectory, projectId, take);
    final updated = indexed.copyWith(
      displayName: normalizedName,
      clearDisplayName:
          clearDisplayName || (normalizedName != null && normalizedName.isEmpty),
      isFavorite: isFavorite,
    );
    final manifest = File(indexed.manifestPath);
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert(updated.toJson()),
      flush: true,
    );
    return updated;
  }

  Future<void> deleteProjectTake(
    ProjectManifest project,
    KtvRecordingSession take,
  ) async {
    final directory = await KtvProjectStorage.resolveProjectDirectory(project);
    await deleteTake(directory, project.id, take);
  }

  /// Deletes only a complete take folder beneath the given project's recordings.
  /// The user interface must obtain explicit confirmation before calling this.
  Future<void> deleteTake(
    Directory projectDirectory,
    String projectId,
    KtvRecordingSession take,
  ) async {
    final folder = await _validatedTakeFolder(projectDirectory, projectId, take);
    await _findIndexedTake(projectDirectory, projectId, take);
    await for (final child in folder.list(recursive: true, followLinks: false)) {
      if (child is Link) {
        throw const FileSystemException('录音包含符号链接，已取消删除');
      }
    }
    await folder.delete(recursive: true);
  }

  Future<KtvRecordingSession> _findIndexedTake(
    Directory projectDirectory,
    String projectId,
    KtvRecordingSession take,
  ) async {
    await _validatedTakeFolder(projectDirectory, projectId, take);
    final indexed = await listFromDirectory(projectDirectory, projectId);
    for (final entry in indexed) {
      if (entry.id == take.id &&
          _samePath(entry.manifestPath, take.manifestPath)) {
        return entry;
      }
    }
    throw const FileSystemException('录音不存在或已发生变化');
  }

  Future<Directory> _validatedTakeFolder(
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
        take.id.contains('\\') ||
        take.id.contains(Platform.pathSeparator) ||
        take.id.contains('..') ||
        await FileSystemEntity.type(folder.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !_inside(folder, File(take.manifestPath)) ||
        !_inside(folder, File(take.micStemPath))) {
      throw const FileSystemException('录音路径不安全，已取消操作');
    }
    return folder;
  }

  bool _samePath(String left, String right) {
    final leftPath = File(left).absolute.path;
    final rightPath = File(right).absolute.path;
    return Platform.isWindows
        ? leftPath.toLowerCase() == rightPath.toLowerCase()
        : leftPath == rightPath;
  }

  bool _inside(Directory directory, File file) {
    final root = directory.absolute.path;
    final path = file.absolute.path;
    return path.startsWith('$root${Platform.pathSeparator}');
  }
}
