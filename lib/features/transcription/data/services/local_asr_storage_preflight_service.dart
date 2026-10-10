import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';
import '../../domain/services/transcription_profile_resolver.dart';

class LocalAsrStoragePreflightService implements AsrStoragePreflightService {
  static const int _mib = 1024 * 1024;
  static const int _gib = 1024 * _mib;

  // These are intentionally conservative working budgets, not download-size
  // claims. They include installed runtimes/models plus room needed while
  // archives are being downloaded/extracted.
  static const int _whisperInstalledBytes = 4 * _gib;
  static const int _rtxHighestInstalledBytes = 11 * _gib;
  static const int _intelMacHighestInstalledBytes = 8 * _gib;
  static const int _whisperTemporaryBytes = 1 * _gib;
  static const int _rtxHighestTemporaryBytes = 2 * _gib;
  static const int _intelMacHighestTemporaryBytes = 1536 * _mib;
  static const int _safetyMarginBytes = 2 * _gib;

  static const String _qwen17 = 'Qwen/Qwen3-ASR-1.7B';
  static const String _qwen06 = 'Qwen/Qwen3-ASR-0.6B';
  static const String _aligner06 = 'Qwen/Qwen3-ForcedAligner-0.6B';

  final TranscriptionProfileResolver profileResolver;
  final Future<Directory> Function()? managedRootResolver;
  final Future<int?> Function(String path)? freeSpaceReader;

  const LocalAsrStoragePreflightService({
    required this.profileResolver,
    this.managedRootResolver,
    this.freeSpaceReader,
  });

  @override
  Future<AsrStoragePreflightResult> inspect(
    TranscriptionConfig config, {
    AsrRuntimeStatus? runtimeStatus,
  }) async {
    final root = await _managedRoot();
    if (runtimeStatus?.isReady == true) {
      return AsrStoragePreflightResult(
        state: AsrStoragePreflightState.ready,
        managedRoot: root.path,
        estimatedInstalledBytes: await _estimateCurrentRelevantBytes(
          root,
          config,
          runtimeStatus?.profile.profile,
        ),
        existingRelevantBytes: await _estimateCurrentRelevantBytes(
          root,
          config,
          runtimeStatus?.profile.profile,
        ),
        temporaryHeadroomBytes: 0,
        safetyMarginBytes: 0,
        requiredAdditionalBytes: 0,
        availableBytes: await _readFreeSpace(root.path),
        detail: '当前识别环境已经完整就绪，无需为本次使用额外预留安装空间。',
      );
    }

    final resolved = await profileResolver.resolve(config);
    final profile = resolved.profile;
    if (profile == TranscriptionProfilePreference.custom) {
      return AsrStoragePreflightResult(
        state: AsrStoragePreflightState.notApplicable,
        managedRoot: root.path,
        estimatedInstalledBytes: 0,
        existingRelevantBytes: 0,
        temporaryHeadroomBytes: 0,
        safetyMarginBytes: 0,
        requiredAdditionalBytes: 0,
        availableBytes: await _readFreeSpace(root.path),
        detail: '当前为高级自定义方案；外部模型和 runtime 的磁盘空间由用户指定位置决定，因此不进行托管目录拦截。',
      );
    }

    final budget = _budgetFor(resolved.config, profile);
    if (budget == null) {
      return AsrStoragePreflightResult(
        state: AsrStoragePreflightState.notApplicable,
        managedRoot: root.path,
        estimatedInstalledBytes: 0,
        existingRelevantBytes: 0,
        temporaryHeadroomBytes: 0,
        safetyMarginBytes: 0,
        requiredAdditionalBytes: 0,
        availableBytes: await _readFreeSpace(root.path),
        detail: '当前硬件 Profile 没有 LyricForge 托管安装预算，因此不会错误阻止高级手工配置。',
      );
    }

    final existing = await _estimateCurrentRelevantBytes(
      root,
      resolved.config,
      profile,
    );
    final missingPersistent = math.max(
      0,
      budget.installedBytes - math.min(existing, budget.installedBytes),
    );
    final required =
        missingPersistent + budget.temporaryBytes + _safetyMarginBytes;
    final available = await _readFreeSpace(root.path);

    if (available == null) {
      return AsrStoragePreflightResult(
        state: AsrStoragePreflightState.unknown,
        managedRoot: root.path,
        estimatedInstalledBytes: budget.installedBytes,
        existingRelevantBytes: existing,
        temporaryHeadroomBytes: budget.temporaryBytes,
        safetyMarginBytes: _safetyMarginBytes,
        requiredAdditionalBytes: required,
        availableBytes: null,
        detail: '无法读取当前磁盘可用空间。不会误拦安装，但仍建议保留足够空间并避免安装过程中清理 .part 断点文件。',
      );
    }

    final enough = available >= required;
    return AsrStoragePreflightResult(
      state: enough
          ? AsrStoragePreflightState.sufficient
          : AsrStoragePreflightState.insufficient,
      managedRoot: root.path,
      estimatedInstalledBytes: budget.installedBytes,
      existingRelevantBytes: existing,
      temporaryHeadroomBytes: budget.temporaryBytes,
      safetyMarginBytes: _safetyMarginBytes,
      requiredAdditionalBytes: required,
      availableBytes: available,
      detail: enough
          ? '空间充足，可以开始安装。预算包含目标模型/runtime、安装过程临时空间和 2 GB 安全余量。'
          : '磁盘空间不足，已阻止开始大型模型下载，避免数小时后才因空间耗尽失败。',
    );
  }

  _StorageBudget? _budgetFor(
    TranscriptionConfig config,
    TranscriptionProfilePreference profile,
  ) {
    if (config.mode == TranscriptionMode.whisperOnly) {
      return const _StorageBudget(
        installedBytes: _whisperInstalledBytes,
        temporaryBytes: _whisperTemporaryBytes,
      );
    }

    return switch (profile) {
      TranscriptionProfilePreference.rtx5080HighQuality =>
        const _StorageBudget(
          installedBytes: _rtxHighestInstalledBytes,
          temporaryBytes: _rtxHighestTemporaryBytes,
        ),
      TranscriptionProfilePreference.intelMacHighQuality =>
        const _StorageBudget(
          installedBytes: _intelMacHighestInstalledBytes,
          temporaryBytes: _intelMacHighestTemporaryBytes,
        ),
      _ => null,
    };
  }

  Future<int> _estimateCurrentRelevantBytes(
    Directory root,
    TranscriptionConfig config,
    TranscriptionProfilePreference? profile,
  ) async {
    final targets = <FileSystemEntity>[
      Directory(_join(root.path, ['models', 'whisper'])),
      Directory(_join(root.path, ['ffmpeg'])),
      Directory(_join(root.path, ['whisper'])),
      Directory(_join(root.path, ['bundle'])),
    ];

    if (config.mode == TranscriptionMode.highestQuality) {
      final qwenModel = switch (profile) {
        TranscriptionProfilePreference.intelMacHighQuality => _qwen06,
        _ => _qwen17,
      };
      targets.addAll([
        _modelDirectory(root, qwenModel),
        _modelDirectory(root, _aligner06),
      ]);
    }

    var total = 0;
    for (final target in targets) {
      total += await _entitySize(target);
    }

    final downloads = Directory(_join(root.path, ['downloads']));
    if (await downloads.exists()) {
      try {
        await for (final entity in downloads.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.part')) {
            total += await entity.length();
          }
        }
      } catch (_) {
        // A concurrent cleanup should make the estimate more conservative, not
        // break the preflight.
      }
    }
    return total;
  }

  Future<int> _entitySize(FileSystemEntity entity) async {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 0;
    if (type == FileSystemEntityType.file) {
      return File(entity.path).length();
    }
    if (type != FileSystemEntityType.directory) return 0;

    var total = 0;
    try {
      await for (final child in Directory(entity.path).list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is File) total += await child.length();
      }
    } catch (_) {
      // Treat unreadable files as not reusable so the estimate errs toward
      // requiring more free space.
    }
    return total;
  }

  Future<int?> _readFreeSpace(String path) async {
    final injected = freeSpaceReader;
    if (injected != null) return injected(path);

    try {
      if (Platform.isWindows) {
        final escaped = path.replaceAll("'", "''");
        final script =
            "\$p=(Resolve-Path -LiteralPath '$escaped').Path; "
            '\$root=[System.IO.Path]::GetPathRoot(\$p); '
            '([System.IO.DriveInfo]::new(\$root)).AvailableFreeSpace';
        final result = await Process.run(
          'powershell.exe',
          ['-NoProfile', '-NonInteractive', '-Command', script],
        );
        if (result.exitCode != 0) return null;
        return parseWindowsAvailableBytes(result.stdout.toString());
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('df', ['-Pk', path]);
        if (result.exitCode != 0) return null;
        return parseDfAvailableBytes(result.stdout.toString());
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static int? parseWindowsAvailableBytes(String output) {
    for (final line in output.split(RegExp(r'[\r\n]+'))) {
      final parsed = int.tryParse(line.trim());
      if (parsed != null && parsed >= 0) return parsed;
    }
    return null;
  }

  static int? parseDfAvailableBytes(String output) {
    final lines = output
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final columns = lines.last.split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    final availableKilobytes = int.tryParse(columns[3]);
    if (availableKilobytes == null || availableKilobytes < 0) return null;
    return availableKilobytes * 1024;
  }

  Future<Directory> _managedRoot() async {
    final injected = managedRootResolver;
    if (injected != null) {
      final root = await injected();
      await root.create(recursive: true);
      return root;
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory(_join(support.path, ['LyricForge', 'ASRRuntime']));
    await root.create(recursive: true);
    return root;
  }

  Directory _modelDirectory(Directory root, String modelId) {
    final directoryName = modelId.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '--',
    );
    return Directory(_join(root.path, ['models', 'qwen', directoryName]));
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

class _StorageBudget {
  final int installedBytes;
  final int temporaryBytes;

  const _StorageBudget({
    required this.installedBytes,
    required this.temporaryBytes,
  });
}
