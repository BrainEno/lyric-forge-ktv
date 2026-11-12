import '../../../lyrics/domain/proofreading/project_proofread_evidence.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/independent_asr_evidence.dart';
import '../../domain/models/transcription_models.dart';
import 'asr_evidence_audio_verifier.dart';
import 'project_transcription_input.dart';

/// Reuses a verified single-input pair only when the primary remains the draft.
/// Otherwise, the original pair is exposed solely for read-only inspection;
/// no original transcript becomes evidence about the edited or fused draft.
class VerifiedProjectProofreadEvidenceLoader {
  final ProjectRepository projects;
  final Future<String> Function(ProjectManifest) resolveInput;
  final Future<AsrEvidenceAudioStatus> Function({
    required Object? rawEvidence,
    required String? currentAudioPath,
  })
  verifyAudio;

  VerifiedProjectProofreadEvidenceLoader({
    required this.projects,
    Future<String> Function(ProjectManifest)? resolveInput,
    Future<AsrEvidenceAudioStatus> Function({
      required Object? rawEvidence,
      required String? currentAudioPath,
    })?
    verifyAudio,
  }) : resolveInput = resolveInput ?? resolveProjectTranscriptionInput,
       verifyAudio = verifyAudio ?? const AsrEvidenceAudioVerifier().verify;

  Future<ProjectProofreadEvidenceResult> load({
    required String projectId,
    required int expectedProjectRevision,
    required LyricDocument draft,
  }) async {
    ProjectProofreadEvidenceResult unavailable(
      ProjectProofreadEvidenceStatus status,
    ) => ProjectProofreadEvidenceResult.unavailable(status);
    final project = await projects.getProjectById(projectId);
    if (project == null || project.revision != expectedProjectRevision) {
      return unavailable(ProjectProofreadEvidenceStatus.projectChanged);
    }
    final raw =
        project.lyricDocument?.metadata[IndependentAsrEvidence.metadataKey];
    if (raw == null)
      return unavailable(ProjectProofreadEvidenceStatus.missingEvidence);
    final evidence = IndependentAsrEvidence.tryParse(raw);
    if (evidence == null ||
        !_independentEngines(evidence) ||
        !_validTranscript(evidence.primary) ||
        !_validTranscript(evidence.secondary)) {
      return unavailable(ProjectProofreadEvidenceStatus.invalidEvidence);
    }
    if ((evidence.primary.globalOffset ?? Duration.zero) != Duration.zero ||
        (evidence.secondary.globalOffset ?? Duration.zero) != Duration.zero ||
        (draft.globalOffset ?? Duration.zero) != Duration.zero) {
      return unavailable(ProjectProofreadEvidenceStatus.unsupportedOffsets);
    }
    final matchesPrimary = _matchesPrimary(draft, evidence.primary);
    if (evidence.sourceAudioSha256 == null) {
      return unavailable(ProjectProofreadEvidenceStatus.unverifiedAudio);
    }
    String input;
    try {
      input = await resolveInput(project);
    } on TranscriptionException catch (error) {
      if (error.kind != TranscriptionFailureKind.input) rethrow;
      return unavailable(ProjectProofreadEvidenceStatus.audioUnavailable);
    }
    final audioStatus = await verifyAudio(
      rawEvidence: raw,
      currentAudioPath: input,
    );
    if (audioStatus != AsrEvidenceAudioStatus.audioMatches) {
      return unavailable(switch (audioStatus) {
        AsrEvidenceAudioStatus.missingEvidence =>
          ProjectProofreadEvidenceStatus.missingEvidence,
        AsrEvidenceAudioStatus.invalidEvidence =>
          ProjectProofreadEvidenceStatus.invalidEvidence,
        AsrEvidenceAudioStatus.unverified =>
          ProjectProofreadEvidenceStatus.unverifiedAudio,
        AsrEvidenceAudioStatus.audioUnavailable =>
          ProjectProofreadEvidenceStatus.audioUnavailable,
        AsrEvidenceAudioStatus.audioChanged =>
          ProjectProofreadEvidenceStatus.audioChanged,
        AsrEvidenceAudioStatus.audioMatches => throw StateError('unreachable'),
      });
    }
    try {
      if (await resolveInput(project) != input) {
        return unavailable(
          ProjectProofreadEvidenceStatus.audioSelectionChanged,
        );
      }
    } on TranscriptionException catch (error) {
      if (error.kind != TranscriptionFailureKind.input) rethrow;
      return unavailable(ProjectProofreadEvidenceStatus.audioUnavailable);
    }
    final latest = await projects.getProjectById(projectId);
    if (latest == null || latest.revision != expectedProjectRevision) {
      return unavailable(ProjectProofreadEvidenceStatus.projectChanged);
    }
    if (!matchesPrimary) {
      return ProjectProofreadEvidenceResult.auditOnly(
        primary: evidence.primary.toDocument(),
        primaryEngine: evidence.primary.engine,
        secondary: evidence.secondary.toDocument(),
        secondaryEngine: evidence.secondary.engine,
        capturedAtUtc: evidence.capturedAtUtc,
      );
    }
    return ProjectProofreadEvidenceResult.available(
      secondary: evidence.secondary.toDocument(),
      secondaryEngine: evidence.secondary.engine,
      capturedAtUtc: evidence.capturedAtUtc,
    );
  }

  static bool _independentEngines(IndependentAsrEvidence evidence) {
    bool safe(String engine) => RegExp(r'^[a-z0-9._-]{1,80}$').hasMatch(engine);
    if (!safe(evidence.primary.engine) || !safe(evidence.secondary.engine))
      return false;
    bool qwen(String engine) => engine.startsWith('qwen3-asr-');
    bool whisper(String engine) => engine.startsWith('whisper.cpp-');
    return (qwen(evidence.primary.engine) &&
            whisper(evidence.secondary.engine)) ||
        (whisper(evidence.primary.engine) && qwen(evidence.secondary.engine));
  }

  static bool _validTranscript(IndependentAsrTranscript transcript) {
    Duration? previousStart;
    for (final line in transcript.lines) {
      if (line.text.trim().isEmpty ||
          (previousStart != null && line.startTime < previousStart))
        return false;
      previousStart = line.startTime;
    }
    return true;
  }

  static bool _matchesPrimary(
    LyricDocument draft,
    IndependentAsrTranscript primary,
  ) {
    if (draft.language != primary.language ||
        draft.lines.length != primary.lines.length)
      return false;
    for (var i = 0; i < draft.lines.length; i++) {
      final current = draft.lines[i];
      final original = primary.lines[i];
      if (current.text != original.text ||
          current.startTime != original.startTime ||
          current.endTime != original.endTime ||
          current.confidence != original.confidence ||
          current.confidenceSource != original.confidenceSource)
        return false;
    }
    return true;
  }
}
