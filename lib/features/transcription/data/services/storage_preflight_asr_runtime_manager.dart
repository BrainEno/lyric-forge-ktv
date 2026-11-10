import 'dart:async';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';
import 'local_asr_managed_storage_service.dart';
import 'local_asr_runtime_health_checker.dart';

class StoragePreflightAsrRuntimeManager implements AsrRuntimeManager {
  final AsrRuntimeManager delegate;
  final AsrStoragePreflightService storagePreflightService;
  final AsrRuntimeHealthChecker healthChecker;
  final Future<bool> Function() storageAuthorizationRequired;

  bool _installActive = false;
  bool _delegateInstalling = false;
  bool _cancelRequested = false;
  Future<void>? _pendingCancel;

  StoragePreflightAsrRuntimeManager({
    required this.delegate,
    required this.storagePreflightService,
    AsrRuntimeHealthChecker? healthChecker,
    Future<bool> Function()? storageAuthorizationRequired,
  }) : healthChecker = healthChecker ?? LocalAsrRuntimeHealthChecker(),
       storageAuthorizationRequired =
           storageAuthorizationRequired ??
           LocalAsrManagedStorageService().needsSecurityScopedAuthorization;

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      delegate.progressStream;

  // Keep the existing delegate-facing status until callers have independent
  // cancellation ownership; exposing preflight here would let a different
  // caller cancel this installation.
  @override
  bool get isInstalling => delegate.isInstalling;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    final status = await delegate.inspect(config);
    if (delegate.isInstalling) return status;
    return healthChecker.verify(status);
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) {
    return delegate.repair(config);
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    if (_installActive) {
      throw const TranscriptionException.busy('已有识别环境安装任务正在运行');
    }
    _installActive = true;
    _cancelRequested = false;
    try {
      return await _install(config);
    } catch (_) {
      _checkCancelled();
      rethrow;
    } finally {
      try {
        final pending = _pendingCancel;
        if (pending != null) await pending;
      } finally {
        _pendingCancel = null;
        _delegateInstalling = false;
        _cancelRequested = false;
        _installActive = false;
      }
    }
  }

  Future<TranscriptionConfig> _install(TranscriptionConfig config) async {
    final authorizationRequired = await storageAuthorizationRequired();
    _checkCancelled();
    if (authorizationRequired) {
      throw TranscriptionException.environment(
        'macOS 需要重新授权当前模型存储目录。请点击“更改模型存储位置”，'
        '重新选择当前 ASRRuntime 所在位置的父文件夹；已有 .part 断点文件会继续保留。',
        details: 'security-scoped bookmark missing for custom managed ASR root',
      );
    }

    AsrRuntimeStatus? status;
    try {
      final raw = await delegate.inspect(config);
      _checkCancelled();
      status = await healthChecker.verify(raw);
      _checkCancelled();
      final invalidated = await healthChecker.invalidateManagedFailures(status);
      _checkCancelled();
      if (invalidated) {
        healthChecker.clearCache();
        status = await delegate.inspect(config);
      }
    } catch (_) {
      _checkCancelled();
      // Storage preflight must still run when environment inspection itself is
      // incomplete. The preflight service will use its conservative budget.
    }

    _checkCancelled();
    final storage = await storagePreflightService.inspect(
      config,
      runtimeStatus: status,
    );
    _checkCancelled();
    if (!storage.canInstall) {
      throw TranscriptionException.environment(
        '磁盘空间不足：安装建议至少可用 '
        '${_formatBytes(storage.requiredAdditionalBytes)}，'
        '当前可用 ${_formatBytes(storage.availableBytes ?? 0)}，'
        '还差 ${_formatBytes(storage.shortfallBytes)}',
        details: _details(storage),
      );
    }

    _delegateInstalling = true;
    late final TranscriptionConfig installed;
    try {
      installed = await delegate.installRecommended(config);
    } finally {
      _delegateInstalling = false;
    }
    _checkCancelled();
    healthChecker.clearCache();

    AsrRuntimeStatus finalStatus;
    try {
      finalStatus = await healthChecker.verify(
        await delegate.inspect(installed),
      );
    } catch (_) {
      _checkCancelled();
      return installed;
    }
    _checkCancelled();

    if (finalStatus.isReady) {
      await healthChecker.cleanupInstallerCache(finalStatus.managedRoot);
      _checkCancelled();
      return installed;
    }

    if (installed.mode == TranscriptionMode.highestQuality &&
        _whisperBaselineReady(finalStatus)) {
      await healthChecker.cleanupInstallerCache(finalStatus.managedRoot);
      _checkCancelled();
      final repaired = await delegate.repair(
        installed.copyWith(mode: TranscriptionMode.whisperOnly),
      );
      _checkCancelled();
      return repaired;
    }

    final failed = finalStatus.components
        .where((component) => component.state != AsrRuntimeComponentState.ready)
        .map((component) => '${component.label}: ${component.detail}')
        .join('; ');
    throw TranscriptionException.environment(
      '识别环境文件已经安装，但运行健康检查失败',
      details: failed,
    );
  }

  bool _whisperBaselineReady(AsrRuntimeStatus status) {
    const required = {
      AsrRuntimeComponent.ffmpeg,
      AsrRuntimeComponent.whisperRuntime,
      AsrRuntimeComponent.whisperModel,
    };
    for (final component in status.components) {
      if (required.contains(component.component) &&
          component.state != AsrRuntimeComponentState.ready) {
        return false;
      }
    }
    return required.every(
      (requiredComponent) => status.components.any(
        (component) =>
            component.component == requiredComponent &&
            component.state == AsrRuntimeComponentState.ready,
      ),
    );
  }

  String _details(AsrStoragePreflightResult storage) {
    return 'requiredAdditionalBytes=${storage.requiredAdditionalBytes}, '
        'availableBytes=${storage.availableBytes}, '
        'shortfallBytes=${storage.shortfallBytes}, '
        'managedRoot=${storage.managedRoot}';
  }

  String _formatBytes(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(gib >= 10 ? 1 : 2)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB';
  }

  void _checkCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException.cancelled('识别环境安装已取消');
    }
  }

  @override
  Future<void> cancel() async {
    if (!_installActive) return;
    _cancelRequested = true;
    if (_delegateInstalling) {
      await (_pendingCancel ??= delegate.cancel());
    }
  }
}
