import 'dart:async';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';
import 'local_asr_runtime_health_checker.dart';

class StoragePreflightAsrRuntimeManager implements AsrRuntimeManager {
  final AsrRuntimeManager delegate;
  final AsrStoragePreflightService storagePreflightService;
  final AsrRuntimeHealthChecker healthChecker;

  StoragePreflightAsrRuntimeManager({
    required this.delegate,
    required this.storagePreflightService,
    AsrRuntimeHealthChecker? healthChecker,
  }) : healthChecker = healthChecker ?? LocalAsrRuntimeHealthChecker();

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => delegate.progressStream;

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
    AsrRuntimeStatus? status;
    try {
      final raw = await delegate.inspect(config);
      status = await healthChecker.verify(raw);
      final invalidated = await healthChecker.invalidateManagedFailures(status);
      if (invalidated) {
        healthChecker.clearCache();
        status = await delegate.inspect(config);
      }
    } catch (_) {
      // Storage preflight must still run when environment inspection itself is
      // incomplete. The preflight service will use its conservative budget.
    }

    final storage = await storagePreflightService.inspect(
      config,
      runtimeStatus: status,
    );
    if (!storage.canInstall) {
      throw TranscriptionException(
        '磁盘空间不足：安装建议至少可用 '
        '${_formatBytes(storage.requiredAdditionalBytes)}，'
        '当前可用 ${_formatBytes(storage.availableBytes ?? 0)}，'
        '还差 ${_formatBytes(storage.shortfallBytes)}',
        details: _details(storage),
      );
    }

    final installed = await delegate.installRecommended(config);
    healthChecker.clearCache();

    final finalStatus = await healthChecker.verify(
      await delegate.inspect(installed),
    );
    if (finalStatus.isReady) {
      await healthChecker.cleanupInstallerCache(finalStatus.managedRoot);
      return installed;
    }

    if (installed.mode == TranscriptionMode.highestQuality &&
        _whisperBaselineReady(finalStatus)) {
      await healthChecker.cleanupInstallerCache(finalStatus.managedRoot);
      return delegate.repair(
        installed.copyWith(mode: TranscriptionMode.whisperOnly),
      );
    }

    final failed = finalStatus.components
        .where((component) => component.state != AsrRuntimeComponentState.ready)
        .map((component) => '${component.label}: ${component.detail}')
        .join('; ');
    throw TranscriptionException(
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

  @override
  Future<void> cancel() => delegate.cancel();
}
