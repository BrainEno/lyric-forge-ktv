import '../models/transcription_models.dart';

enum AsrRuntimeComponent {
  ffmpeg,
  whisperRuntime,
  whisperModel,
  qwenRuntime,
  qwenModel,
  qwenAligner,
}

enum AsrRuntimeComponentState {
  ready,
  missing,
  installing,
  failed,
  unavailable,
}

/// 安装进度所处的阶段。UI 必须把“读取并校验本机已有文件”和“从网络
/// 下载”分开呈现，避免用户把 SHA-256 校验误认为正在重复下载。
enum AsrRuntimeInstallPhase {
  preparing,
  checkingExisting,
  downloading,
  verifying,
  installing,
}

class AsrRuntimeComponentStatus {
  final AsrRuntimeComponent component;
  final AsrRuntimeComponentState state;
  final String label;
  final String detail;
  final String? resolvedPath;
  final double? progress;

  const AsrRuntimeComponentStatus({
    required this.component,
    required this.state,
    required this.label,
    required this.detail,
    this.resolvedPath,
    this.progress,
  });
}

class AsrRuntimeStatus {
  /// Components needed before any lyrics can be produced locally.
  ///
  /// Whisper is the baseline: every hardware profile can install it, and the
  /// highest-quality mode falls back to it when the optional second engine is
  /// unavailable. Only these components may block recognition outright.
  static const Set<AsrRuntimeComponent> baselineComponents = {
    AsrRuntimeComponent.ffmpeg,
    AsrRuntimeComponent.whisperRuntime,
    AsrRuntimeComponent.whisperModel,
  };

  final ResolvedTranscriptionProfile profile;
  final List<AsrRuntimeComponentStatus> components;
  final String managedRoot;

  const AsrRuntimeStatus({
    required this.profile,
    required this.components,
    required this.managedRoot,
  });

  /// Every component the profile needs is installed, including the optional
  /// second engine.
  bool get isReady => components.every(
    (component) => component.state == AsrRuntimeComponentState.ready,
  );

  /// The Whisper baseline is installed, so a run can produce a draft even if
  /// the optional second engine is missing or broken.
  bool get isBaselineReady => _ready(baselineComponents);

  /// Baseline components that would block recognition, for error messages.
  List<AsrRuntimeComponentStatus> get missingBaselineComponents => components
      .where(
        (component) =>
            baselineComponents.contains(component.component) &&
            component.state != AsrRuntimeComponentState.ready,
      )
      .toList(growable: false);

  bool _ready(Set<AsrRuntimeComponent> required) => components
      .where((component) => required.contains(component.component))
      .every((component) => component.state == AsrRuntimeComponentState.ready);

  int get readyCount => components
      .where((component) => component.state == AsrRuntimeComponentState.ready)
      .length;
}

class AsrRuntimeInstallProgress {
  final AsrRuntimeComponent? component;
  final double progress;
  final String message;
  final AsrRuntimeInstallPhase phase;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
  final Duration? estimatedRemaining;

  const AsrRuntimeInstallProgress({
    this.component,
    required this.progress,
    required this.message,
    this.phase = AsrRuntimeInstallPhase.preparing,
    this.downloadedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.estimatedRemaining,
  });

  bool get hasTransferMetrics =>
      downloadedBytes != null && totalBytes != null && totalBytes! > 0;

  bool get isCheckingExisting =>
      phase == AsrRuntimeInstallPhase.checkingExisting ||
      phase == AsrRuntimeInstallPhase.verifying;

  bool get isDownloading =>
      phase == AsrRuntimeInstallPhase.downloading || hasTransferMetrics;
}

abstract class AsrRuntimeManager {
  Stream<AsrRuntimeInstallProgress> get progressStream;
  bool get isInstalling;

  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config);

  Future<TranscriptionConfig> installRecommended(TranscriptionConfig config);

  Future<TranscriptionConfig> repair(TranscriptionConfig config);

  Future<void> cancel();
}
