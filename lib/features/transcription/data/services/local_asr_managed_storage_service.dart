import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/services/asr_managed_storage_service.dart';

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
    if (path is! String ||
        path.trim().isEmpty ||
        bookmark is! String ||
        bookmark.trim().isEmpty) {
      throw const FileSystemException('macOS 无法恢复模型目录访问授权，请重新选择模型存储位置');
    }
    return AsrSecurityScopedBookmarkAccess(
      path: path.trim(),
      bookmark: bookmark.trim(),
    );
  }
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
class LocalAsrManagedStorageService implements AsrManagedStorageService {
  final Future<Directory> Function()? supportDirectoryResolver;
  final AsrSecurityScopedBookmarkBridge? securityScopedBookmarkBridge;
  final bool Function()? isMacOSResolver;
  bool _moving = false;

  LocalAsrManagedStorageService({
    this.supportDirectoryResolver,
    AsrSecurityScopedBookmarkBridge? securityScopedBookmarkBridge,
    this.isMacOSResolver,
  }) : securityScopedBookmarkBridge =
           securityScopedBookmarkBridge ??
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
    var securityScopedParent = configured.securityScopedParent;
    var securityScopedBookmark = configured.securityScopedBookmark;
    final bookmark = configured.securityScopedBookmark;
    final bridge = securityScopedBookmarkBridge;
    if (_isMacOS &&
        bookmark != null &&
        bookmark.trim().isNotEmpty &&
        bridge != null) {
      final restored = await bridge.restoreAndStart(bookmark);
      final restoredParent = Directory(restored.path).absolute;
      root = _rootFromRestoredParent(
        restoredParent: restoredParent,
        configured: configured,
      );
      securityScopedParent = restoredParent.path;
      securityScopedBookmark = restored.bookmark;
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

    // Older builds could poison the persisted pointer by appending another
    // LyricForge/ASRRuntime below the real ASRRuntime (for example
    // D:\Models\LyricForge\ASRRuntime\LyricForge\ASRRuntime).  Merely
    // creating that nested directory forever makes every later refresh miss
    // the multi-GB models one level above it.  Recover only when the outer
    // ancestor is recognisable as at least as complete an ASR root; the
    // nested partial tree is left in place rather than deleted implicitly.
    final recovered = await _unwrapRepeatedManagedRoot(root);
    if (recovered != null && !_samePath(recovered.path, root.path)) {
      root = recovered;
      await _writeConfiguredRoot(
        root.path,
        securityScopedParent: securityScopedParent,
        securityScopedBookmark: securityScopedBookmark,
      );
    }

    await root.create(recursive: true);
    return root;
  }

  Future<Directory> defaultRoot() async {
    final support = await _supportDirectory();
    return Directory(
      _join(support.path, ['LyricForge', 'ASRRuntime']),
    ).absolute;
  }

  @override
  Future<AsrManagedStorageLocation> inspect() async {
    final active = await resolveRoot();
    final fallback = await defaultRoot();
    final bytes = await _directoryBytes(active);
    return AsrManagedStorageLocation(
      activeRoot: active.path,
      defaultRoot: fallback.path,
      managedBytes: bytes,
      isDefault: _samePath(active.path, fallback.path),
    );
  }

  @override
  Future<AsrManagedStorageMoveResult?> discoverAndAdoptExisting() async {
    final candidates = await _findExistingRoots(
      await _discoverySeedDirectories(),
    );
    if (candidates.isEmpty) return null;

    final best = candidates.first.root;
    final configured = await _readConfiguredRoot();
    final fallback = await defaultRoot();
    var securityScopedParent = configured?.securityScopedParent;
    var securityScopedBookmark = configured?.securityScopedBookmark;

    if (_isMacOS) {
      final alreadyAuthorized =
          configured != null &&
          _samePath(best.path, configured.managedRoot) &&
          (configured.securityScopedBookmark?.trim().isNotEmpty ?? false);
      if (!_samePath(best.path, fallback.path) && !alreadyAuthorized) {
        throw FileSystemException(
          '已找到已有 ASRRuntime，但 macOS 需要先通过“粘贴路径识别”或“浏览已有 ASRRuntime”授权该文件夹',
          best.path,
        );
      }
      if (!alreadyAuthorized) {
        securityScopedParent = null;
        securityScopedBookmark = null;
      }
    } else {
      securityScopedParent = null;
      securityScopedBookmark = null;
    }

    return _moveToRoot(
      best,
      securityScopedParent: securityScopedParent,
      securityScopedBookmark: securityScopedBookmark,
    );
  }

  @override
  Future<AsrManagedStorageMoveResult> adoptExistingAt(
    String selectedPath,
  ) async {
    final authorized = await _authorizeSelectedPath(
      selectedPath,
      emptyMessage: '没有输入已有模型路径',
    );
    final selected = await _directoryForSelection(authorized.path);
    final candidates = await _findExistingRoots([
      selected,
    ], expandAllSeedChildren: true);
    if (candidates.isEmpty) {
      throw FileSystemException(
        '未在该路径及其相邻 LyricForge/ASRRuntime 目录中识别到已有 ASRRuntime；'
        '可粘贴完整的 ASRRuntime 路径，或改为一键自动查找',
        selected.path,
      );
    }
    return _moveToRoot(
      candidates.first.root,
      securityScopedParent: authorized.securityScopedParent,
      securityScopedBookmark: authorized.securityScopedBookmark,
    );
  }

  @override
  Future<AsrManagedStorageMoveResult> moveToParent(
    String selectedParent, {
    void Function(int copiedBytes, int totalBytes)? onProgress,
  }) async {
    final authorized = await _authorizeSelectedPath(
      selectedParent,
      emptyMessage: '没有选择新的模型存储目录',
    );
    final selected = await _directoryForSelection(authorized.path);
    final target = await _resolveSelectionTarget(selected);
    return _moveToRoot(
      target,
      securityScopedParent: authorized.securityScopedParent,
      securityScopedBookmark: authorized.securityScopedBookmark,
      onProgress: onProgress,
    );
  }

  Future<
    ({
      String path,
      String? securityScopedParent,
      String? securityScopedBookmark,
    })
  >
  _authorizeSelectedPath(
    String selectedPath, {
    required String emptyMessage,
  }) async {
    var path = _cleanSelectedPath(selectedPath);
    if (path.isEmpty) {
      throw FileSystemException(emptyMessage);
    }

    String? bookmark;
    if (_isMacOS) {
      final bridge = securityScopedBookmarkBridge;
      if (bridge == null) {
        throw const FileSystemException('macOS 模型目录授权服务不可用');
      }
      final access = await bridge.createAndStart(path);
      path = access.path;
      bookmark = access.bookmark;
    }

    return (
      path: path,
      securityScopedParent: _isMacOS ? Directory(path).absolute.path : null,
      securityScopedBookmark: bookmark,
    );
  }

  Future<Directory> _directoryForSelection(String selectedPath) async {
    final type = await FileSystemEntity.type(selectedPath, followLinks: false);
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      return File(selectedPath).parent.absolute;
    }
    return Directory(selectedPath).absolute;
  }

  String _cleanSelectedPath(String selectedPath) {
    var value = selectedPath.trim();
    while (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.toLowerCase().startsWith('file://')) {
      try {
        value = Uri.parse(value).toFilePath();
      } catch (_) {
        // Keep the original text so the normal filesystem error names it.
      }
    }
    return value;
  }

  @override
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

      final targetIsExistingRoot = await _looksLikeManagedAsrRoot(target);

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
          adoptedExisting: targetIsExistingRoot,
        );
      }

      // A previous LyricForge install may already have downloaded the full
      // runtime/models on another drive. Switching the pointer is enough:
      // the runtime managers resolve every component relative to this root,
      // so repair/inspect will rediscover those files without a second
      // multi-GB copy (and without deleting either tree).
      //
      // Adoption deliberately precedes the overlap guard. If an older build
      // nested the active root below the real root, the real target is an
      // ancestor of the source; copying would be unsafe, but a pointer-only
      // switch to that recognisable ancestor is exactly the recovery path.
      if (targetIsExistingRoot) {
        await _assertWritable(target);
        await _writeConfiguredRoot(
          target.path,
          securityScopedParent: securityScopedParent,
          securityScopedBookmark: securityScopedBookmark,
        );
        return AsrManagedStorageMoveResult(
          sourceRoot: source.path,
          targetRoot: target.path,
          copiedBytes: 0,
          copiedFiles: 0,
          moved: true,
          oldRootRetained: sourceStats.files > 0 || sourceStats.bytes > 0,
          adoptedExisting: true,
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
        _join(targetParent.path, [
          '.ASRRuntime.migrating-${DateTime.now().microsecondsSinceEpoch}',
        ]),
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
          throw FileSystemException('迁移校验失败：复制后的文件数量或总大小与原目录不一致', staging.path);
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

  Future<Directory> _resolveSelectionTarget(Directory selected) async {
    final existing = await _findExistingRoots([
      selected,
    ], expandAllSeedChildren: true);
    if (existing.isNotEmpty) return existing.first.root;

    final selectedName = _pathBasename(selected.path).toLowerCase();
    if (_isAsrRuntimeName(selectedName)) {
      return await _unwrapRepeatedManagedRoot(selected) ?? selected;
    }
    if (_isLyricForgeName(selectedName)) {
      return Directory(_join(selected.path, ['ASRRuntime'])).absolute;
    }
    return Directory(
      _join(selected.path, ['LyricForge', 'ASRRuntime']),
    ).absolute;
  }

  Future<List<_ExistingRootCandidate>> _findExistingRoots(
    Iterable<Directory> seeds, {
    bool expandAllSeedChildren = false,
  }) async {
    final candidatePaths = <String, String>{};

    void addCandidate(Directory directory) {
      final absolute = directory.absolute;
      candidatePaths.putIfAbsent(
        _normalizedPath(absolute.path),
        () => absolute.path,
      );
    }

    void addCandidatesForBase(Directory base) {
      for (final candidate in _candidateRootsForBase(base)) {
        addCandidate(candidate);
      }
    }

    for (final seed in seeds) {
      final absoluteSeed = seed.absolute;
      addCandidatesForBase(absoluteSeed);

      final seedChildren = await _immediateChildDirectories(absoluteSeed);
      for (final child in seedChildren) {
        if (expandAllSeedChildren ||
            _isFilesystemRoot(absoluteSeed) ||
            _isLikelyContainerName(_pathBasename(child.path))) {
          addCandidatesForBase(child);
        }
      }

      // A selection may be the managed root itself, a model subdirectory, or
      // a file's parent. Likewise, a poisoned nested active root has the
      // real root among its ancestors. Checking each ancestor (and the
      // canonical child roots below it) makes those inputs forgiving without
      // recursively walking an entire drive.
      for (final ancestor in _ancestorDirectories(absoluteSeed)) {
        addCandidatesForBase(ancestor);
        final children = await _immediateChildDirectories(ancestor);
        for (final child in children) {
          if (_isFilesystemRoot(ancestor) ||
              _isLikelyContainerName(_pathBasename(child.path))) {
            addCandidatesForBase(child);
          }
        }
      }
    }

    final configured = await _readConfiguredRoot();
    final fallback = await defaultRoot();
    final preferredPaths = <String>{
      if (configured != null) _normalizedPath(configured.managedRoot),
      _normalizedPath(fallback.path),
    };

    final candidates = <_ExistingRootCandidate>[];
    for (final path in candidatePaths.values) {
      final root = Directory(path).absolute;
      final score = await _scoreManagedAsrRoot(root);
      if (score < 4) continue;
      candidates.add(
        _ExistingRootCandidate(
          root: root,
          score: score,
          preferred: preferredPaths.contains(_normalizedPath(root.path)),
          isRepeatedNestedRoot: _repeatedManagedRootAncestor(root) != null,
        ),
      );
    }

    candidates.sort((left, right) {
      if (left.isRepeatedNestedRoot != right.isRepeatedNestedRoot) {
        return left.isRepeatedNestedRoot ? 1 : -1;
      }
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      if (left.preferred != right.preferred) {
        return left.preferred ? -1 : 1;
      }
      final byLength = left.root.path.length.compareTo(right.root.path.length);
      if (byLength != 0) return byLength;
      return left.root.path.compareTo(right.root.path);
    });
    return candidates;
  }

  List<Directory> _candidateRootsForBase(Directory base) {
    final absolute = base.absolute;
    final name = _pathBasename(absolute.path).toLowerCase();
    final candidates = <Directory>[];
    void add(Directory directory) {
      final value = directory.absolute;
      if (!candidates.any((item) => _samePath(item.path, value.path))) {
        candidates.add(value);
      }
    }

    if (_isAsrRuntimeName(name)) {
      add(absolute);
      var current = absolute;
      while (true) {
        final outer = _repeatedManagedRootAncestor(current);
        if (outer == null) break;
        add(outer);
        current = outer;
      }
      return candidates;
    }
    if (_isLyricForgeName(name)) {
      add(Directory(_join(absolute.path, ['ASRRuntime'])));
      return candidates;
    }

    add(absolute);
    add(Directory(_join(absolute.path, ['ASRRuntime'])));
    add(Directory(_join(absolute.path, ['LyricForge', 'ASRRuntime'])));
    // The user's real layout is D:\Models\LyricForge\ASRRuntime. When the
    // seed is a whole drive, this one extra canonical branch finds it while
    // keeping discovery bounded to named locations.
    add(
      Directory(_join(absolute.path, ['Models', 'LyricForge', 'ASRRuntime'])),
    );
    return candidates;
  }

  Future<List<Directory>> _discoverySeedDirectories() async {
    final seeds = <Directory>[];
    void add(Directory directory) {
      final absolute = directory.absolute;
      if (!seeds.any((item) => _samePath(item.path, absolute.path))) {
        seeds.add(absolute);
      }
    }

    final configured = await _readConfiguredRoot();
    if (configured != null) {
      add(Directory(configured.managedRoot));
    }
    add(await defaultRoot());
    add(await _supportDirectory());

    final environment = Platform.environment;
    final home = Platform.isWindows
        ? environment['USERPROFILE'] ?? environment['HOME']
        : environment['HOME'] ?? environment['USERPROFILE'];
    if (home != null && home.trim().isNotEmpty) {
      final homeDirectory = Directory(home.trim());
      add(homeDirectory);
      for (final child in const [
        'Downloads',
        'Documents',
        'Models',
        'LyricForge',
      ]) {
        add(Directory(_join(homeDirectory.path, [child])));
      }
    }

    if (Platform.isWindows) {
      for (var code = 'C'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++) {
        final drive = Directory('${String.fromCharCode(code)}:\\');
        try {
          if (await drive.exists()) add(drive);
        } catch (_) {
          // A disconnected removable/network drive must not make discovery fail.
        }
      }
    } else if (Platform.isMacOS) {
      add(Directory('/Volumes'));
    } else if (Platform.isLinux) {
      add(Directory('/mnt'));
      add(Directory('/media'));
    }
    return seeds;
  }

  List<Directory> _ancestorDirectories(Directory directory) {
    final ancestors = <Directory>[];
    var current = directory.absolute.parent;
    while (true) {
      ancestors.add(current);
      final parent = current.parent;
      if (_samePath(parent.path, current.path)) break;
      current = parent;
    }
    return ancestors;
  }

  Future<List<Directory>> _immediateChildDirectories(
    Directory directory,
  ) async {
    final children = <Directory>[];
    try {
      if (!await directory.exists()) return children;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory) children.add(entity.absolute);
      }
    } catch (_) {
      return children;
    }
    return children;
  }

  bool _isFilesystemRoot(Directory directory) {
    final absolute = directory.absolute;
    return _samePath(absolute.path, absolute.parent.path);
  }

  bool _isLikelyContainerName(String name) {
    final normalized = name.toLowerCase();
    return const {
          'lyricforge',
          'models',
          'model',
          'ai',
          'downloads',
          'download',
          'documents',
          'data',
          'apps',
          'applications',
          'programdata',
          'users',
          'home',
          'volumes',
          'mnt',
          'media',
        }.contains(normalized) ||
        _isAsrRuntimeName(normalized) ||
        normalized.contains('lyricforge') ||
        normalized.contains('model');
  }

  bool _isAsrRuntimeName(String value) => value.toUpperCase() == 'ASRRUNTIME';

  bool _isLyricForgeName(String value) => value.toUpperCase() == 'LYRICFORGE';

  Directory? _repeatedManagedRootAncestor(Directory root) {
    final absolute = root.absolute;
    final parent = absolute.parent;
    final grandparent = parent.parent;
    if (!_isAsrRuntimeName(_pathBasename(absolute.path)) ||
        !_isLyricForgeName(_pathBasename(parent.path)) ||
        !_isAsrRuntimeName(_pathBasename(grandparent.path))) {
      return null;
    }
    return grandparent.absolute;
  }

  Future<Directory?> _unwrapRepeatedManagedRoot(Directory root) async {
    var current = root.absolute;
    if (_repeatedManagedRootAncestor(current) == null) return null;

    final originalScore = await _scoreManagedAsrRoot(current);
    Directory? recovered;
    while (true) {
      final outer = _repeatedManagedRootAncestor(current);
      if (outer == null) break;
      final outerScore = await _scoreManagedAsrRoot(outer);
      if (outerScore < 4 || outerScore < originalScore) break;
      recovered = outer;
      current = outer;
    }
    return recovered;
  }

  Future<bool> _looksLikeManagedAsrRoot(Directory root) async {
    return await _scoreManagedAsrRoot(root) >= 4;
  }

  /// Scores layout-specific evidence that [root] is a LyricForge ASR root.
  ///
  /// A merely non-empty directory scores zero and keeps taking the existing
  /// conflict path, so unrelated user files are never silently treated as an
  /// ASR environment. Scores also let bounded discovery prefer the complete
  /// outer root over a newly created, nearly empty nested root.
  Future<int> _scoreManagedAsrRoot(Directory root) async {
    var score = 0;

    Future<bool> fileExists(List<String> relative) async {
      try {
        return await File(_join(root.path, relative)).exists();
      } catch (_) {
        return false;
      }
    }

    try {
      if (!await root.exists()) return 0;

      if (_isAsrRuntimeName(_pathBasename(root.path))) score += 1;
      if (await fileExists(['.runtime-health-v1.json'])) score += 4;
      if (await fileExists(['models', 'whisper', 'ggml-large-v3.bin'])) {
        score += 5;
      } else if (await fileExists([
        'models',
        'whisper',
        'ggml-large-v3.bin.part',
      ])) {
        score += 2;
      }
      if (await fileExists(['bundle', 'bin', 'qwen3-asr']) ||
          await fileExists(['bundle', 'bin', 'qwen3-asr.exe'])) {
        score += 3;
      }
      if (await fileExists(['bundle', 'bin', 'whisper-cli']) ||
          await fileExists(['bundle', 'bin', 'whisper-cli.exe']) ||
          await fileExists(['whisper', 'bin', 'whisper-cli']) ||
          await fileExists(['whisper', 'bin', 'whisper-cli.exe']) ||
          await fileExists(['whisper', 'whisper-cli']) ||
          await fileExists(['whisper', 'whisper-cli.exe'])) {
        score += 3;
      }
      if (await fileExists(['bundle', 'bin', 'ffmpeg']) ||
          await fileExists(['bundle', 'bin', 'ffmpeg.exe']) ||
          await fileExists(['ffmpeg', 'bin', 'ffmpeg']) ||
          await fileExists(['ffmpeg', 'bin', 'ffmpeg.exe'])) {
        score += 1;
      }
      if (await fileExists(['state', 'runtime-build-revision.txt'])) {
        score += 3;
      }
      if (await fileExists(['downloads', 'asr-runtime.zip'])) {
        score += 2;
      } else if (await fileExists(['downloads', 'asr-runtime.zip.part'])) {
        score += 1;
      }

      final state = Directory(_join(root.path, ['state']));
      if (await state.exists()) {
        await for (final entity in state.list(followLinks: false)) {
          if (entity is File &&
              _pathBasename(entity.path).startsWith('qwen_') &&
              entity.path.endsWith('.ready.json')) {
            score += 3;
            break;
          }
        }
      }

      final qwenModels = Directory(_join(root.path, ['models', 'qwen']));
      if (!await qwenModels.exists()) return score;
      var modelEvidence = 0;
      await for (final entity in qwenModels.list(followLinks: false)) {
        if (entity is! Directory) continue;
        var directoryEvidence = 0;
        const managedModelDirectoryNames = {
          'Qwen--Qwen3-ASR-1.7B',
          'Qwen--Qwen3-ASR-0.6B',
          'Qwen--Qwen3-ForcedAligner-0.6B',
        };
        if (managedModelDirectoryNames.contains(_pathBasename(entity.path))) {
          await for (final child in entity.list(followLinks: false)) {
            if (child is File) {
              directoryEvidence = 3;
              break;
            }
          }
        }
        if (await File(
          _join(entity.path, ['.lyricforge-model.json']),
        ).exists()) {
          modelEvidence += 4;
          if (modelEvidence >= 8) break;
          continue;
        }

        // A model downloaded by an older build (or copied from a Hugging
        // Face snapshot into the managed layout) may not have LyricForge's
        // marker yet. Normal file names + a weight file are sufficient to
        // adopt the root; runtime repair/install still performs its own
        // stricter completeness and SHA-256 checks before using the model.
        final hasConfig = await File(
          _join(entity.path, ['config.json']),
        ).exists();
        if (hasConfig) {
          await for (final child in entity.list(followLinks: false)) {
            if (child is File && child.path.endsWith('.safetensors')) {
              directoryEvidence = 4;
              break;
            }
          }
        }
        modelEvidence += directoryEvidence;
        if (modelEvidence >= 8) break;
      }
      return score + (modelEvidence > 8 ? 8 : modelEvidence);
    } catch (_) {
      return score;
    }
  }

  Directory _rootFromRestoredParent({
    required Directory restoredParent,
    required _ConfiguredManagedRoot configured,
  }) {
    final legacyRoot = Directory(
      _join(restoredParent.path, ['LyricForge', 'ASRRuntime']),
    ).absolute;
    final configuredParent = configured.securityScopedParent;
    if (configuredParent == null || configuredParent.trim().isEmpty) {
      return legacyRoot;
    }

    final configuredRoot = Directory(configured.managedRoot).absolute.path;
    final parentPath = Directory(configuredParent).absolute.path;
    if (_samePath(configuredRoot, parentPath)) return restoredParent;

    final separator = Platform.pathSeparator;
    final normalizedRoot = _normalizedPath(configuredRoot);
    final normalizedParent = _normalizedPath(parentPath);
    final prefix = normalizedParent.endsWith(separator)
        ? normalizedParent
        : '$normalizedParent$separator';
    if (!normalizedRoot.startsWith(prefix)) return legacyRoot;

    final relative = configuredRoot.substring(prefix.length);
    final segments = relative
        .split(separator)
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return restoredParent;
    return Directory(_join(restoredParent.path, segments)).absolute;
  }

  String _pathBasename(String path) {
    final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
    final parts = trimmed.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? trimmed : parts.last;
  }

  Future<void> _copyTree({
    required Directory source,
    required Directory target,
    required void Function(int bytes) onFileCopied,
  }) async {
    if (!await source.exists()) return;
    await target.create(recursive: true);

    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
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
      _join(directory.path, [
        '.lyricforge-write-${DateTime.now().microsecondsSinceEpoch}',
      ]),
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
        securityScopedParent: parent is String && parent.trim().isNotEmpty
            ? parent.trim()
            : null,
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
        'securityScopedBookmark': ?securityScopedBookmark,
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

class _ExistingRootCandidate {
  final Directory root;
  final int score;
  final bool preferred;
  final bool isRepeatedNestedRoot;

  const _ExistingRootCandidate({
    required this.root,
    required this.score,
    required this.preferred,
    required this.isRepeatedNestedRoot,
  });
}
