enum AsrEndToEndSmokeStage {
  validatingAudio,
  preparingEnvironment,
  creatingProject,
  transcribing,
  verifyingResult,
  completed,
  cancelling,
}

class AsrEndToEndSmokeProgress {
  final AsrEndToEndSmokeStage stage;
  final double progress;
  final String message;

  const AsrEndToEndSmokeProgress({
    required this.stage,
    required this.progress,
    required this.message,
  });
}

class AsrEndToEndSmokeResult {
  final String projectId;
  final String projectName;
  final String sourcePath;
  final int lyricLineCount;
  final bool environmentInstalled;

  const AsrEndToEndSmokeResult({
    required this.projectId,
    required this.projectName,
    required this.sourcePath,
    required this.lyricLineCount,
    required this.environmentInstalled,
  });
}

/// Runs the same production path used by a real song import, from local runtime
/// readiness through persisted editable lyrics. A successful result therefore
/// means the generated project is ready to open in the lyric editor.
abstract class AsrEndToEndSmokeTestService {
  Stream<AsrEndToEndSmokeProgress> get progressStream;
  bool get isRunning;

  Future<AsrEndToEndSmokeResult> run(String audioPath);

  Future<void> cancel();
}
