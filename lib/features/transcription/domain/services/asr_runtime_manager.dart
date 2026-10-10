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
  final ResolvedTranscriptionProfile profile;
  final List<AsrRuntimeComponentStatus> components;
  final String managedRoot;

  const AsrRuntimeStatus({
    required this.profile,
    required this.components,
    required this.managedRoot,
  });

  bool get isReady =>
      components.every((component) => component.state == AsrRuntimeComponentState.ready);

  int get readyCount =>
      components.where((component) => component.state == AsrRuntimeComponentState.ready).length;
}

class AsrRuntimeInstallProgress {
  final AsrRuntimeComponent? component;
  final double progress;
  final String message;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
  final Duration? estimatedRemaining;

  const AsrRuntimeInstallProgress({
    this.component,
    required this.progress,
    required this.message,
    this.downloadedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.estimatedRemaining,
  });

  bool get hasTransferMetrics =>
      downloadedBytes != null && totalBytes != null && totalBytes! > 0;
}

abstract class AsrRuntimeManager {
  Stream<AsrRuntimeInstallProgress> get progressStream;
  bool get isInstalling;

  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config);

  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  );

  Future<TranscriptionConfig> repair(
    TranscriptionConfig config,
  );

  Future<void> cancel();
}
