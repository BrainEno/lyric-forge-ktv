import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_resource_coordinator.dart';
import '../../domain/services/asr_runtime_manager.dart';

/// One installation caller's facade over a shared runtime manager.
///
/// All installation callers sharing [delegate] must use distinct instances
/// backed by the same [resources], and must not install through the delegate
/// directly. Otherwise ownership and cancellation cannot be guaranteed. The
/// coordinator only protects participating operations in the same isolate.
/// Repair and inspection deliberately pass through: recognition can call them
/// while it already holds a lease. Independent repairs still need coordination.
class CoordinatedAsrInstallManager implements AsrRuntimeManager {
  final AsrRuntimeManager delegate;
  final AsrResourceCoordinator resources;

  bool _ownsInstallation = false;
  Future<void>? _pendingCancel;

  CoordinatedAsrInstallManager({
    required this.delegate,
    required this.resources,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      delegate.progressStream;

  @override
  bool get isInstalling => _ownsInstallation || delegate.isInstalling;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) =>
      delegate.inspect(config);

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) =>
      delegate.repair(config);

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    if (_ownsInstallation) {
      throw const TranscriptionException.busy('已有识别环境安装任务正在运行');
    }
    final lease = resources.tryAcquire(AsrResourceUse.installation);
    if (lease == null) {
      throw const TranscriptionException.busy('识别资源正在使用，请稍后重试');
    }
    _ownsInstallation = true;
    try {
      return await delegate.installRecommended(config);
    } finally {
      try {
        final pending = _pendingCancel;
        if (pending != null) await pending;
      } finally {
        _pendingCancel = null;
        _ownsInstallation = false;
        lease.release();
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (!_ownsInstallation) return;
    await (_pendingCancel ??= Future.sync(delegate.cancel));
  }
}
