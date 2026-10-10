import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AsrSecurityScopedBookmarkAccess {
  final String path;
  final String bookmark;

  const AsrSecurityScopedBookmarkAccess({
    required this.path,
    required this.bookmark,
  });
}

abstract interface class AsrSecurityScopedBookmarkBridge {
  Future<AsrSecurityScopedBookmarkAccess> createAndStart(String path);

  Future<AsrSecurityScopedBookmarkAccess> restoreAndStart(String bookmark);
}

class MethodChannelAsrSecurityScopedBookmarkBridge
    implements AsrSecurityScopedBookmarkBridge {
  static const MethodChannel _channel = MethodChannel(
    'lyric_forge/asr_security_scoped_storage',
  );

  const MethodChannelAsrSecurityScopedBookmarkBridge();

  @override
  Future<AsrSecurityScopedBookmarkAccess> createAndStart(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'createAndStartBookmark',
      {'path': path},
    );
    return _decode(result);
  }

  @override
  Future<AsrSecurityScopedBookmarkAccess> restoreAndStart(
    String bookmark,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'restoreAndStartBookmark',
      {'bookmark': bookmark},
    );
    return _decode(result);
  }

  AsrSecurityScopedBookmarkAccess _decode(Map<String, dynamic>? result) {
    final path = result?['path'];
    final bookmark = result?['bookmark'];
    if (path is! String || path.trim().isEmpty ||
        bookmark is! String || bookmark.trim().isEmpty) {
      throw const FileSystemException(
        'macOS 无法恢复模型目录访问授权，请重新选择模型存储位置',
      );
    }
    return AsrSecurityScopedBookmarkAccess(
      path: path.trim(),
      bookmark: bookmark.trim(),
    );
  }
}

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
/// On sandboxed macOS builds a custom location also stores an app-scoped
/// security-scoped bookmark. This is required because a raw path selected by
/// NSOpenPanel is not a persistent permission across application launches.
/// Migration is copy-first: the old environment remains untouched until a
/// staging copy has the same file count and byte total and the new location
/// pointer has been persisted successfully.
class LocalAsrManagedStorageService {
  final Future<Directory> Function()? supportDirectoryResolver;
  final AsrSecurityScopedBookmarkBridge? securityScopedBookmarkBridge;
  final bool Function()? isMacOSResolver;
  bool _moving = false;

  LocalAsrManagedStorageService({
    this.supportDirectoryResolver,
    AsrSecurityScopedBookmarkBridge? securityScopedBookmarkBridge,
    this.isMacOSResolver,
  }) : securityScopedBookmarkBridge = securityScopedBookmarkBridge ??
            (Platform.isMacOS
                ? const MethodChannelAsrSecurityScopedBookmarkBridge()
                : null);

  bool get isMoving => _moving;

  bool get _isMacOS => isMacOSResolver?.call() ?? Platform.isMacOS;

  Future<bool> needsSecurityScopedAuthorization() async {
    if (!_isMacOS) return false;
    final configured = await _readConfiguredRoot();
    if (configured == null) return false;
    final fallback = await defaultRoot();
    if (_samePath(configured.managedRoot, fallback.path)) return false;
    return configured.securityScopedBookmark == null ||
        configured.securityScopedBookmark!.trim().isEmpty;
  }

  Future<Directory> resolveRoot() async {
    final configured = await _readConfiguredRoot();
    if (configured == null) {
      final root = await defaultRoot();
      await root.create(recursive: true);
      return root;
    }

    var root = Directory(configured.managedRoot).absolute;
    final bookmark = configured.securityScopedBookmark;
    final bridge = securityScopedBookmarkBridge;
    if (_isMacOS && bookmark != null && bookmark.trim().isNotEmpty && bridge != null) {
      final restored = await bridge.restoreAndStart(bookmark);
      final restoredParent = Directory(restored.path).absolute;
      root = Directory(
        _join(restoredParent.path, ['LyricForge', 'ASRRuntime']),
      ).absolute;
      if (!_samePath(root.path, configured.managedRoot) ||
          restored.bookmark != bookmark ||
          configured.securityScopedParent != restoredParent.path) {
        await _writeConfiguredRoot(
          root.path,
          securityScopedParent: restoredParent.path,
          securityScopedBookmark: restored.bookmark,
        );
      }
    }

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
    var parent = selectedParent.trim();
    if (parent.isEmpty) {
      throw const FileSystemException('没有选择新的模型存储目录');
    }

    String? bookmark;
    if (_isMacOS) {
      final bridge = securityScopedBookmarkBridge;
      if (bridge == null) {
        throw const FileSystemException('macOS 模型目录授权服务不可用');
      }
      final access = await bridge.createAndStart(parent);
      parent = access.path;
      bookmark = access.bookmark;
    }

    final target = Directory(
      _join(Directory(parent).absolute.path, ['LyricForge', 'ASRRuntime']),
    );
    return _moveToRoot(
      target,
      securityScopedParent: _isMacOS ? Directory(parent).absolute.path : null,
      securityScopedBookmark: bookmark,
      onProgress: onProgress,
    );
  }

  Future<AsrManagedStorageMoveResult> moveToDefault({
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    return _moveToRoot(await defaultRoot(), onProgress: onProgress);
  }

  Future<AsrManagedStorageMoveResult> _moveToRoot(
    Directory requestedTarget, {
    String? securityScopedParent,
    String? securityScopedBookmark,
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    if (_moving) {
      throw const FileSystemException('ASR 模型目录正在迁移');
    }
    _moving = true;

    try {
      // moveToParent creates/starts the macOS bookmark before this call. That is
      // intentional: it lets a legacy schema-v1 path be re-authorized by
      // selecting the same parent, after which resolveRoot can access existing
      // .part files again without moving or redownloading them.
      final source = await resolveRoot();
      final target = requestedTarget.absolute;
      final sourceStats = await _treeStats(source);

      if (_samePath(source.path, target.path)) {
        await _writeConfiguredRoot(
          target.path,
          securityScopedParent: securityScopedParent,
          securityScopedBookmark: securityScopedBookmark,
        );
        return AsrManagedStorageMoveResult(
          sourceRoot: source.path,
          targetRoot: target.path,
          copiedBytes: sourceStats.bytes,
          copiedFiles: sourceStats.files,
          moved: false,
        );
      }

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
          await _writeConfiguredRoot(
            target.path,
            securityScopedParent: securityScopedParent,
            securityScopedBookmark: securityScopedBookmark,
          );
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
        } catch (_) {}
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

  Future<_ConfiguredManagedRoot?> _readConfiguredRoot() async {
    final file = await _configFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion != 1 && schemaVersion != 2) return null;
      final value = decoded['managedRoot'];
      if (value is! String || value.trim().isEmpty) return null;
      final parent = decoded['securityScopedParent'];
      final bookmark = decoded['securityScopedBookmark'];
      return _ConfiguredManagedRoot(
        managedRoot: value.trim(),
        securityScopedParent:
            parent is String && parent.trim().isNotEmpty ? parent.trim() : null,
        securityScopedBookmark: bookmark is String && bookmark.trim().isNotEmpty
            ? bookmark.trim()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeConfiguredRoot(
    String root, {
    String? securityScopedParent,
    String? securityScopedBookmark,
  }) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'managedRoot': Directory(root).absolute.path,
        if (securityScopedParent != null)
          'securityScopedParent': Directory(securityScopedParent).absolute.path,
        if (securityScopedBookmark != null)
          'securityScopedBookmark': securityScopedBookmark,
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

class _ConfiguredManagedRoot {
  final String managedRoot;
  final String? securityScopedParent;
  final String? securityScopedBookmark;

  const _ConfiguredManagedRoot({
    required this.managedRoot,
    this.securityScopedParent,
    this.securityScopedBookmark,
  });
}

class _TreeStats {
  final int files;
  final int bytes;

  const _TreeStats({required this.files, required this.bytes});
}
