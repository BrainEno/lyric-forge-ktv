import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/services/asr_runtime_manager.dart';

class RuntimeExecutableHealth {
  final bool healthy;
  final String detail;

  const RuntimeExecutableHealth({
    required this.healthy,
    required this.detail,
  });
}

typedef RuntimeHealthProbe = Future<RuntimeExecutableHealth> Function(
  String executable,
  AsrRuntimeComponent component,
);

abstract class AsrRuntimeHealthChecker {
  Future<AsrRuntimeStatus> verify(AsrRuntimeStatus status);

  Future<bool> invalidateManagedFailures(AsrRuntimeStatus status);

  Future<void> cleanupInstallerCache(String managedRoot);

  void clearCache();
}

class LocalAsrRuntimeHealthChecker implements AsrRuntimeHealthChecker {
  static const int _schemaVersion = 1;
  static const Duration _healthyTtl = Duration(hours: 6);
  static const Duration _failedTtl = Duration(minutes: 2);
  static const Duration _commandOnlyTtl = Duration(minutes: 5);
  static const Duration _probeTimeout = Duration(seconds: 10);

  final RuntimeHealthProbe? probe;
  final DateTime Function() now;

  final Map<String, _HealthCacheEntry> _cache = {};
  String? _loadedRoot;
  bool _cacheDirty = false;

  LocalAsrRuntimeHealthChecker({
    this.probe,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<AsrRuntimeStatus> verify(AsrRuntimeStatus status) async {
    if (status.managedRoot.trim().isNotEmpty) {
      await _loadCache(status.managedRoot);
    }

    final components = <AsrRuntimeComponentStatus>[];
    for (final component in status.components) {
      if (!_isRuntimeComponent(component.component) ||
          component.state != AsrRuntimeComponentState.ready ||
          component.resolvedPath == null ||
          component.resolvedPath!.trim().isEmpty) {
        components.add(component);
        continue;
      }

      final health = await _healthFor(
        component.component,
        component.resolvedPath!,
        status.managedRoot,
      );
      if (health.healthy) {
        components.add(component);
      } else {
        components.add(
          AsrRuntimeComponentStatus(
            component: component.component,
            state: AsrRuntimeComponentState.failed,
            label: component.label,
            detail: '文件存在，但启动自检失败：${health.detail}',
            resolvedPath: component.resolvedPath,
          ),
        );
      }
    }

    await _persistCache(status.managedRoot);
    return AsrRuntimeStatus(
      profile: status.profile,
      components: components,
      managedRoot: status.managedRoot,
    );
  }

  @override
  Future<bool> invalidateManagedFailures(AsrRuntimeStatus status) async {
    final root = status.managedRoot.trim();
    if (root.isEmpty) return false;

    var changed = false;
    for (final component in status.components) {
      if (component.state != AsrRuntimeComponentState.failed) continue;
      final path = component.resolvedPath;
      if (path == null || !_isInside(path, root)) continue;

      final target = switch (component.component) {
        AsrRuntimeComponent.qwenRuntime ||
        AsrRuntimeComponent.whisperRuntime => Directory(_join(root, ['bundle'])),
        AsrRuntimeComponent.ffmpeg => Directory(_join(root, ['ffmpeg'])),
        _ => null,
      };
      if (target == null || !await target.exists()) continue;

      try {
        await target.delete(recursive: true);
        changed = true;
      } catch (_) {
        // Leave the original health failure intact. The installer will surface
        // a concrete error rather than deleting external or unrelated files.
      }
    }

    if (changed) clearCache();
    return changed;
  }

  @override
  Future<void> cleanupInstallerCache(String managedRoot) async {
    final root = managedRoot.trim();
    if (root.isEmpty) return;
    final downloads = Directory(_join(root, ['downloads']));
    if (!await downloads.exists()) return;

    const disposableNames = {
      'asr-runtime.zip',
      'ffmpeg.zip',
      'whisper-b5130-x64.zip',
    };
    try {
      await for (final entity in downloads.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _basename(entity.path);
        if (!disposableNames.contains(name)) continue;
        await entity.delete();
      }
    } catch (_) {
      // Cache cleanup is best effort and must never turn a healthy install into
      // a failure. `.part` files are intentionally not touched.
    }
  }

  @override
  void clearCache() {
    _cache.clear();
    _loadedRoot = null;
    _cacheDirty = false;
  }

  Future<RuntimeExecutableHealth> _healthFor(
    AsrRuntimeComponent component,
    String executable,
    String managedRoot,
  ) async {
    final fingerprint = await _fingerprint(
      component,
      executable,
      managedRoot,
    );
    final key = '${component.name}|$executable';
    final cached = _cache[key];
    if (cached != null &&
        cached.fingerprint == fingerprint &&
        now().difference(cached.checkedAt) <= _ttlFor(cached, fingerprint)) {
      return RuntimeExecutableHealth(
        healthy: cached.healthy,
        detail: cached.detail,
      );
    }

    final runner = probe ?? _probeExecutable;
    final result = await runner(executable, component);
    _cache[key] = _HealthCacheEntry(
      fingerprint: fingerprint,
      healthy: result.healthy,
      detail: result.detail,
      checkedAt: now(),
    );
    _cacheDirty = true;
    return result;
  }

  Duration _ttlFor(_HealthCacheEntry entry, String fingerprint) {
    if (fingerprint.startsWith('command:')) return _commandOnlyTtl;
    return entry.healthy ? _healthyTtl : _failedTtl;
  }

  Future<RuntimeExecutableHealth> _probeExecutable(
    String executable,
    AsrRuntimeComponent component,
  ) async {
    final arguments = switch (component) {
      AsrRuntimeComponent.ffmpeg => const ['-version'],
      AsrRuntimeComponent.whisperRuntime || AsrRuntimeComponent.qwenRuntime =>
        const ['--help'],
      _ => const <String>[],
    };

    Process? process;
    try {
      process = await Process.start(executable, arguments);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        _probeTimeout,
        onTimeout: () {
          process?.kill();
          return -999;
        },
      );
      final stdoutText = await stdoutFuture;
      final stderrText = await stderrFuture;
      if (exitCode == 0) {
        return const RuntimeExecutableHealth(
          healthy: true,
          detail: '启动自检通过',
        );
      }
      if (exitCode == -999) {
        return const RuntimeExecutableHealth(
          healthy: false,
          detail: '启动自检超时',
        );
      }
      return RuntimeExecutableHealth(
        healthy: false,
        detail: '退出码 $exitCode${_outputSuffix(stderrText, stdoutText)}',
      );
    } catch (error) {
      return RuntimeExecutableHealth(
        healthy: false,
        detail: _compact(error.toString()),
      );
    } finally {
      if (process != null) {
        process.kill();
      }
    }
  }

  String _outputSuffix(String stderrText, String stdoutText) {
    final value = stderrText.trim().isNotEmpty ? stderrText : stdoutText;
    if (value.trim().isEmpty) return '';
    return '：${_compact(value)}';
  }

  String _compact(String value) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 220) return oneLine;
    return '${oneLine.substring(0, 217)}...';
  }

  Future<String> _fingerprint(
    AsrRuntimeComponent component,
    String executable,
    String managedRoot,
  ) async {
    final file = File(executable);
    if (!await file.exists()) return 'command:$executable';

    final stat = await file.stat();
    final dependencyRoot = _dependencyRoot(component, executable, managedRoot);
    if (dependencyRoot == null || !await dependencyRoot.exists()) {
      return 'file:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    }

    var count = 0;
    var totalBytes = 0;
    var latestModified = 0;
    try {
      await for (final entity in dependencyRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final child = await entity.stat();
        count += 1;
        totalBytes += child.size;
        if (child.modified.millisecondsSinceEpoch > latestModified) {
          latestModified = child.modified.millisecondsSinceEpoch;
        }
      }
    } catch (_) {
      return 'file:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    }
    return 'tree:${stat.size}:${stat.modified.millisecondsSinceEpoch}:'
        '$count:$totalBytes:$latestModified';
  }

  Directory? _dependencyRoot(
    AsrRuntimeComponent component,
    String executable,
    String managedRoot,
  ) {
    if (!_isInside(executable, managedRoot)) return null;
    return switch (component) {
      AsrRuntimeComponent.qwenRuntime || AsrRuntimeComponent.whisperRuntime =>
        Directory(_join(managedRoot, ['bundle'])),
      AsrRuntimeComponent.ffmpeg => Directory(_join(managedRoot, ['ffmpeg'])),
      _ => null,
    };
  }

  bool _isRuntimeComponent(AsrRuntimeComponent component) {
    return component == AsrRuntimeComponent.ffmpeg ||
        component == AsrRuntimeComponent.whisperRuntime ||
        component == AsrRuntimeComponent.qwenRuntime;
  }

  bool _isInside(String path, String root) {
    final normalizedPath = _normalize(path);
    final normalizedRoot = _normalize(root);
    if (normalizedPath == normalizedRoot) return true;
    return normalizedPath.startsWith('$normalizedRoot/');
  }

  String _normalize(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows ? value.toLowerCase() : value;
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

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  Future<void> _loadCache(String managedRoot) async {
    if (_loadedRoot == managedRoot) return;
    _cache.clear();
    _loadedRoot = managedRoot;
    _cacheDirty = false;

    final file = File(_join(managedRoot, ['.runtime-health-v1.json']));
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != _schemaVersion) {
        return;
      }
      final entries = decoded['entries'];
      if (entries is! Map<String, dynamic>) return;
      for (final item in entries.entries) {
        final value = item.value;
        if (value is! Map<String, dynamic>) continue;
        final fingerprint = value['fingerprint'] as String?;
        final healthy = value['healthy'] as bool?;
        final detail = value['detail'] as String?;
        final checkedAtMs = value['checkedAtMs'] as int?;
        if (fingerprint == null ||
            healthy == null ||
            detail == null ||
            checkedAtMs == null) {
          continue;
        }
        _cache[item.key] = _HealthCacheEntry(
          fingerprint: fingerprint,
          healthy: healthy,
          detail: detail,
          checkedAt: DateTime.fromMillisecondsSinceEpoch(checkedAtMs),
        );
      }
    } catch (_) {
      // A corrupt cache is ignored; the next inspect performs real probes.
    }
  }

  Future<void> _persistCache(String managedRoot) async {
    if (!_cacheDirty || managedRoot.trim().isEmpty) return;
    try {
      final file = File(_join(managedRoot, ['.runtime-health-v1.json']));
      await file.parent.create(recursive: true);
      final entries = <String, dynamic>{};
      for (final item in _cache.entries) {
        entries[item.key] = {
          'fingerprint': item.value.fingerprint,
          'healthy': item.value.healthy,
          'detail': item.value.detail,
          'checkedAtMs': item.value.checkedAt.millisecondsSinceEpoch,
        };
      }
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': _schemaVersion,
          'entries': entries,
        }),
        flush: true,
      );
      _cacheDirty = false;
    } catch (_) {
      // Health checks remain authoritative even if the cache cannot be saved.
    }
  }
}

class _HealthCacheEntry {
  final String fingerprint;
  final bool healthy;
  final String detail;
  final DateTime checkedAt;

  const _HealthCacheEntry({
    required this.fingerprint,
    required this.healthy,
    required this.detail,
    required this.checkedAt,
  });
}
