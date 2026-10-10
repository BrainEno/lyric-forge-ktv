import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/asr_storage_preflight_service.dart';

class StoragePreflightAsrRuntimeManager implements AsrRuntimeManager {
  final AsrRuntimeManager delegate;
  final AsrStoragePreflightService storagePreflightService;

  const StoragePreflightAsrRuntimeManager({
    required this.delegate,
    required this.storagePreflightService,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream => delegate.progressStream;

  @override
  bool get isInstalling => delegate.isInstalling;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) {
    return delegate.inspect(config);
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
      status = await delegate.inspect(config);
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
        '磁盘空间不足，已停止安装识别环境',
        details: _details(storage),
      );
    }

    return delegate.installRecommended(config);
  }

  String _details(AsrStoragePreflightResult storage) {
    return 'requiredAdditionalBytes=${storage.requiredAdditionalBytes}, '
        'availableBytes=${storage.availableBytes}, '
        'shortfallBytes=${storage.shortfallBytes}, '
        'managedRoot=${storage.managedRoot}';
  }

  @override
  Future<void> cancel() => delegate.cancel();
}
