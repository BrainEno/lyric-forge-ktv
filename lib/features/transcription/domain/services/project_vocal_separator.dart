import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../models/transcription_models.dart';
import '../models/vocal_separation_models.dart';

/// Result of the separation step of one recognition run.
class ProjectVocalSeparation {
  final VocalSeparationOutcome outcome;

  /// The audio asset with the new automatic stem linked, when the run
  /// produced one, and the separated accompaniment linked when the project
  /// has none of its own (D-060). The workflow writes it under its run
  /// marker; null means the project needs no change.
  final AudioAsset? updatedAudio;

  const ProjectVocalSeparation(this.outcome, {this.updatedAudio});
}

/// Prepares a lead-vocal stem for a project before recognition (D-043).
///
/// Implementations must not throw for anything but cancellation: every other
/// problem becomes a [VocalSeparationOutcome] and recognition continues on
/// the original mix.
abstract interface class ProjectVocalSeparator {
  /// Whether this device can separate at all (D-060); false hides
  /// 自动生成伴奏.
  bool get supportsCurrentPlatform;

  /// Separates (or reuses, or skips) for [project], writing stems under
  /// [workDirectory]. Progress is reported as [TranscriptionStage.preprocessing].
  ///
  /// With [requireAccompaniment], an earlier stem is reused only while its
  /// accompaniment still exists; otherwise the song is separated again.
  ///
  /// Throws [TranscriptionException] of kind
  /// [TranscriptionFailureKind.cancelled] after [cancel].
  Future<ProjectVocalSeparation> separate(
    ProjectManifest project, {
    required TranscriptionConfig config,
    required String workDirectory,
    required void Function(TranscriptionProgress progress) onProgress,
    bool requireAccompaniment = false,
  });

  /// Stops a running download or separation; [separate] then throws the
  /// cancellation.
  Future<void> cancel();
}
