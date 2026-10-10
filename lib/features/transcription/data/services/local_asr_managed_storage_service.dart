import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AsrManagedStorageLocation {
  final String activeRoot;
  final String defaultRoot;
  final int managedBytes;
  final bool oldRootRetained;

  const AsrManagedStorageLocation({
    required this.activeRoot,
    required this.defaultRoot,
    required this.managedBytes,
    this.oldRootRetained = false,
  });

  bool get isDefault => _samePath(activeRoot, defaultRoot);

  static bool _samePath(String left, String right) {
    return _normalizedPath(left) == _normalizedPath(right);
  }

  static String _normalizedPath(String value) {
    var normalized = Directory(value).absolute.path;
    while (normalized.length > 1 &&
        normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class AsrManagedStorageMoveResult {
  final String sourceRoot;
  final String targetRoot;
  final int copiedBytes;
  final int copiedFiles;
  final bool moved;
  final bool oldRootRetained;

  const AsrManagedStorageMoveResult({
    required this.sourceRoot,
    required this.targetRoot,
    required this.copiedBytes,
    required this.copiedFiles,
    required this.moved,
    this.oldRootRetained = false,
  });
}

/// Owns the single source of truth for LyricForge-managed ASR storage.
///
/// The pointer file deliberately lives beside the default ASRRuntime directory,
/// never inside it, so changing drives cannot orphan the location preference.
/// Migration is copy-first: the old environment remains untouched until a
/// staging copy has the same file count and byte total and the new location
/// pointer has been persisted successfully.
class LocalAsrManagedStorageService {
  final Future<Directory> Function()? supportDirectoryResolver;
  bool _moving = false;

  LocalAsrManagedStorageService({this.supportDirectoryResolver});

  bool get isMoving => _moving;

  Future<Directory> resolveRoot() async {
    final configured = await _readConfiguredRoot();
    final root = configured == null
        ? await defaultRoot()
        : Directory(configured).absolute;
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> defaultRoot() async {
    final support = await _supportDirectory();
    return Directory(_join(support.path, ['LyricForge', 'ASRRuntime'])).absolute;
  }

  Future<AsrManagedStorageLocation> inspect() async {
    final active = await resolveRoot();
    final fallback = await defaultRoot();
    final bytes = await _directoryBytes(active);
    return AsrManagedStorageLocation(
      activeRoot: active.path,
      defaultRoot: fallback.path,
      managedBytes: bytes,
    );
  }

  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    final parent = selectedParent.trim();
    if (parent.isEmpty) {
      throw const FileSystemException('没有选择新的模型存储目录');
    }
    final target = Directory(
      _join(Directory(parent).absolute.path, ['LyricForge', 'ASRRuntime']),
    );
    return _moveToRoot(target, onProgress: onProgress);
  }

  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    return _moveToRoot(await defaultRoot(), onProgress: onProgress);
  }

  Future<AsrManagedStorageMoveResult> _moveToRoot(
    Directory requestedTarget, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    if (_moving) {
      throw const FileSystemException('ASR 模型目录正在迁移');
    }
    _moving = true;

    final source = await resolveRoot();
    final target = requestedTarget.absolute;
    final sourceStats = await _treeStats(source);

    if (_samePath(source.path, target.path)) {
      _moving = false;
      return AsrManagedStorageMoveResult(
        sourceRoot: source.path,
        targetRoot: target.path,
        copiedBytes: sourceStats.bytes,
        copiedFiles: sourceStats.files,
        moved: false,
      );
    }

    try {
      if (_pathsOverlap(source.path, target.path)) {
        throw FileSystemException(
          '目标位置不能位于当前 ASRRuntime 目录内部，也不能包含当前目录，请选择其他文件夹',
          target.path,
        );
      }

      final targetParent = target.parent;
      final staging = Directory(
        _join(
          targetParent.path,
          ['.ASRRuntime.migrating-${DateTime.now().microsecondsSinceEpoch}'],
        ),
      );

      await targetParent.create(recursive: true);
      await _assertWritable(targetParent);

      if (await target.exists()) {
        final targetStats = await _treeStats(target);
        if (targetStats.files > 0 || targetStats.bytes > 0) {
          throw FileSystemException(
            '目标位置已经存在 LyricForge ASRRuntime 数据，请选择其他文件夹',
            target.path,
          );
        }
        await target.delete(recursive: true);
      }

      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      try {
        var copiedBytes = 0;
        await _copyTree(
          source: source,
          target: staging,
          onFileCopied: (bytes) {
            copiedBytes += bytes;
            onProgress?.call(copiedBytes, sourceStats.bytes);
          },
        );

        final copiedStats = await _treeStats(staging);
        if (copiedStats.files != sourceStats.files ||
            copiedStats.bytes != sourceStats.bytes) {
          throw FileSystemException(
            '迁移校验失败：复制后的文件数量或总大小与原目录不一致',
            staging.path,
          );
        }

        await staging.rename(target.path);

        try {
          await _writeConfiguredRoot(target.path);
        } catch (_) {
          if (await target.exists()) {
            await target.delete(recursive: true);
          }
          rethrow;
        }

        var oldRootRetained = false;
        try {
          if (await source.exists()) {
            await source.delete(recursive: true);
          }
        } catch (_) {
          // The new pointer already references a fully verified copy. Keeping the
          // old tree is safe and preferable to failing the migration after the
          // switch. Settings surfaces this so users can clean it manually.
          oldRootRetained = true;
        }

        return AsrManagedStorageMoveResult(
          sourceRoot: source.path,
          targetRoot: target.path,
          copiedBytes: copiedStats.bytes,
          copiedFiles: copiedStats.files,
          moved: true,
          oldRootRetained: oldRootRetained,
        );
      } catch (_) {
        if (await staging.exists()) {
          try {
            await staging.delete(recursive: true);
          } catch (_) {}
        }
        rethrow;
      }
    } finally {
      _moving = false;
    }
  }

  Future<void> _copyTree({
    required Directory source,
    required Directory target,
    required void Function(int bytes) onFileCopied,
  }) async {
    if (!await source.exists()) return;
    await target.create(recursive: true);

    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      final destination = _join(target.path, [name]);

      if (entity is Directory) {
        await _copyTree(
          source: entity,
          target: Directory(destination),
          onFileCopied: onFileCopied,
        );
      } else if (entity is File) {
        final copied = await entity.copy(destination);
        try {
          final modified = await entity.lastModified();
          await copied.setLastModified(modified);
        } catch (_) {
          // Modification times improve health-cache reuse but are not required
          // for a byte-identical managed environment.
        }
        onFileCopied(await copied.length());
      } else if (entity is Link) {
        await Link(destination).create(await entity.target());
      }
    }
  }

  Future<_TreeStats> _treeStats(Directory root) async {
    if (!await root.exists()) return const _TreeStats(files: 0, bytes: 0);
    var files = 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files += 1;
        bytes += await entity.length();
      } else if (entity is Link) {
        files += 1;
      }
    }
    return _TreeStats(files: files, bytes: bytes);
  }

  Future<int> _directoryBytes(Directory root) async {
    return (await _treeStats(root)).bytes;
  }

  Future<void> _assertWritable(Directory directory) async {
    final probe = File(
      _join(directory.path, ['.lyricforge-write-${DateTime.now().microsecondsSinceEpoch}']),
    );
    try {
      await probe.writeAsString('ok', flush: true);
    } finally {
      if (await probe.exists()) {
        await probe.delete();
      }
    }
  }

  Future<String?> _readConfiguredRoot() async {
    final file = await _configFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schemaVersion'] != 1) return null;
      final value = decoded['managedRoot'];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeConfiguredRoot(String root) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'managedRoot': Directory(root).absolute.path,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<File> _configFile() async {
    final support = await _supportDirectory();
    return File(
      _join(support.path, ['LyricForge', 'asr-managed-storage.json']),
    );
  }

  Future<Directory> _supportDirectory() async {
    final injected = supportDirectoryResolver;
    if (injected != null) return injected();
    return getApplicationSupportDirectory();
  }

  bool _samePath(String left, String right) {
    return _normalizedPath(left) == _normalizedPath(right);
  }

  bool _pathsOverlap(String left, String right) {
    final leftNormalized = _normalizedPath(left);
    final rightNormalized = _normalizedPath(right);
    final separator = Platform.pathSeparator;
    return rightNormalized.startsWith('$leftNormalized$separator') ||
        leftNormalized.startsWith('$rightNormalized$separator');
  }

  String _normalizedPath(String value) {
    var normalized = Directory(value).absolute.path;
    while (normalized.length > 1 &&
        normalized.endsWith(Platform.pathSeparator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _join(String base, List<String> parts) {
    var current = base;
    for (final part in parts) {
      current = current.endsWith(Platform.pathSeparator)
          ? '$current$part'
          : '$current${Platform.pathSeparator}$part';
    }
    return current;
  }
}

class _TreeStats {
  final int files;
  final int bytes;

  const _TreeStats({required this.files, required this.bytes});
}
