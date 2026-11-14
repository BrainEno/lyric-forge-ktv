import '../../../lyrics/domain/proofreading/project_proofread_evidence.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/independent_asr_evidence.dart';
import '../../domain/models/chunked_independent_asr_evidence.dart';
import '../../domain/models/transcription_models.dart';
import 'asr_evidence_audio_verifier.dart';
import 'project_transcription_input.dart';
import 'whisper_json_artifact_reader.dart';

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
  final Future<WhisperJsonArtifactReadResult> Function(Object? rawPath)
  readWhisperArtifact;

  VerifiedProjectProofreadEvidenceLoader({
    required this.projects,
    Future<String> Function(ProjectManifest)? resolveInput,
    Future<AsrEvidenceAudioStatus> Function({
      required Object? rawEvidence,
      required String? currentAudioPath,
    })?
    verifyAudio,
    Future<WhisperJsonArtifactReadResult> Function(Object? rawPath)?
    readWhisperArtifact,
  }) : resolveInput = resolveInput ?? resolveProjectTranscriptionInput,
       verifyAudio = verifyAudio ?? const AsrEvidenceAudioVerifier().verify,
       readWhisperArtifact =
           readWhisperArtifact ?? const WhisperJsonArtifactReader().read;

  /// Returns only enough metadata to preselect or explain the project option.
  ///
  /// This quick check does not hash audio and never supplies transcript rows.
  /// [load] repeats the project/draft checks and verifies the selected audio
  /// before returning any transcript for comparison or audit.
  Future<ProjectProofreadEvidenceHint> preview({
    required String projectId,
    required int expectedProjectRevision,
    required LyricDocument draft,
  }) async {
    final project = await projects.getProjectById(projectId);
    if (project == null || project.revision != expectedProjectRevision) {
      return const ProjectProofreadEvidenceHint(
        status: ProjectProofreadEvidenceHintStatus.projectChanged,
      );
    }
    final metadata = project.lyricDocument?.metadata;
    final singleRaw = metadata?[IndependentAsrEvidence.metadataKey];
    final chunkRaw = metadata?[ChunkedIndependentAsrEvidence.metadataKey];
    if (singleRaw == null && chunkRaw == null) {
      return const ProjectProofreadEvidenceHint(
        status: ProjectProofreadEvidenceHintStatus.notFound,
      );
    }
    if (singleRaw != null && chunkRaw != null) {
      return const ProjectProofreadEvidenceHint(
        status: ProjectProofreadEvidenceHintStatus.invalid,
      );
    }
    if ((draft.globalOffset ?? Duration.zero) != Duration.zero) {
      return const ProjectProofreadEvidenceHint(
        status: ProjectProofreadEvidenceHintStatus.unsupportedOffsets,
      );
    }

    if (singleRaw != null) {
      final evidence = IndependentAsrEvidence.tryParse(singleRaw);
      if (evidence == null ||
          !_independentEngines(evidence) ||
          !_validTranscript(evidence.primary) ||
          !_validTranscript(evidence.secondary)) {
        return const ProjectProofreadEvidenceHint(
          status: ProjectProofreadEvidenceHintStatus.invalid,
        );
      }
      if ((evidence.primary.globalOffset ?? Duration.zero) != Duration.zero ||
          (evidence.secondary.globalOffset ?? Duration.zero) != Duration.zero) {
        return const ProjectProofreadEvidenceHint(
          status: ProjectProofreadEvidenceHintStatus.unsupportedOffsets,
        );
      }
      if (evidence.sourceAudioSha256 == null) {
        return const ProjectProofreadEvidenceHint(
          status: ProjectProofreadEvidenceHintStatus.unverifiedAudio,
        );
      }
      return ProjectProofreadEvidenceHint(
        status: _matchesPrimary(draft, evidence.primary)
            ? ProjectProofreadEvidenceHintStatus.currentDraftCandidate
            : ProjectProofreadEvidenceHintStatus.readOnlyOriginalPair,
        primaryEngine: evidence.primary.engine,
        secondaryEngine: evidence.secondary.engine,
        capturedAtUtc: evidence.capturedAtUtc,
      );
    }

    final chunked = ChunkedIndependentAsrEvidence.tryParse(chunkRaw);
    if (chunked == null) {
      return const ProjectProofreadEvidenceHint(
        status: ProjectProofreadEvidenceHintStatus.invalid,
      );
    }
    return ProjectProofreadEvidenceHint(
      status: ProjectProofreadEvidenceHintStatus.chunkSnapshotsOnly,
      chunkCount: chunked.chunks.length,
    );
  }

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
    final metadata = project.lyricDocument?.metadata;
    final singleRaw = metadata?[IndependentAsrEvidence.metadataKey];
    final chunkRaw = metadata?[ChunkedIndependentAsrEvidence.metadataKey];
    if (singleRaw == null && chunkRaw == null) {
      return unavailable(ProjectProofreadEvidenceStatus.missingEvidence);
    }
    // Two simultaneous formats have ambiguous provenance: do not guess which
    // one describes the current project.
    if (singleRaw != null && chunkRaw != null) {
      return unavailable(ProjectProofreadEvidenceStatus.invalidEvidence);
    }
    final raw = singleRaw ?? chunkRaw;
    final evidence = singleRaw == null
        ? null
        : IndependentAsrEvidence.tryParse(singleRaw);
    final chunked = chunkRaw == null
        ? null
        : ChunkedIndependentAsrEvidence.tryParse(chunkRaw);
    if ((singleRaw != null &&
            (evidence == null ||
                !_independentEngines(evidence) ||
                !_validTranscript(evidence.primary) ||
                !_validTranscript(evidence.secondary))) ||
        (chunkRaw != null && chunked == null)) {
      return unavailable(ProjectProofreadEvidenceStatus.invalidEvidence);
    }
    if ((draft.globalOffset ?? Duration.zero) != Duration.zero ||
        (evidence != null &&
            ((evidence.primary.globalOffset ?? Duration.zero) !=
                    Duration.zero ||
                (evidence.secondary.globalOffset ?? Duration.zero) !=
                    Duration.zero))) {
      return unavailable(ProjectProofreadEvidenceStatus.unsupportedOffsets);
    }
    final matchesPrimary =
        evidence != null && _matchesPrimary(draft, evidence.primary);
    if (evidence != null && evidence.sourceAudioSha256 == null) {
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
    if (chunked != null) {
      return ProjectProofreadEvidenceResult.chunkAudit([
        for (final chunk in chunked.chunks)
          ProjectProofreadChunk(
            index: chunk.index,
            start: chunk.start,
            end: chunk.end,
            primary: chunk.globalTranscript(primary: true),
            primaryEngine: chunk.evidence.primary.engine,
            secondary: chunk.globalTranscript(primary: false),
            secondaryEngine: chunk.evidence.secondary.engine,
            capturedAtUtc: chunk.evidence.capturedAtUtc,
          ),
      ]);
    }
    // A valid single-input snapshot is guaranteed above when no chunk exists.
    final single = evidence!;
    if (!matchesPrimary) {
      return ProjectProofreadEvidenceResult.auditOnly(
        primary: single.primary.toDocument(),
        primaryEngine: single.primary.engine,
        secondary: single.secondary.toDocument(),
        secondaryEngine: single.secondary.engine,
        capturedAtUtc: single.capturedAtUtc,
      );
    }
    final secondary = await _loadWhisperArtifactOrSnapshot(
      rawPath: metadata?['whisperRawJsonPath'],
      evidence: single,
    );
    return ProjectProofreadEvidenceResult.available(
      secondary: secondary,
      secondaryEngine: single.secondary.engine,
      capturedAtUtc: single.capturedAtUtc,
    );
  }

  Future<LyricDocument> _loadWhisperArtifactOrSnapshot({
    required Object? rawPath,
    required IndependentAsrEvidence evidence,
  }) async {
    final snapshot = evidence.secondary;
    if (!snapshot.engine.startsWith('whisper.cpp-')) {
      return snapshot.toDocument();
    }
    late final WhisperJsonArtifactReadResult artifact;
    try {
      artifact = await readWhisperArtifact(rawPath);
    } catch (_) {
      return snapshot.toDocument();
    }
    final parsed = artifact.parsed;
    if (!artifact.isLoaded ||
        parsed == null ||
        !_matchesWhisperTranscript(parsed.document, snapshot)) {
      // The inline snapshot is already bounded, audio-verified and tied to the
      // current primary draft. A missing/stale raw file cannot invalidate it.
      return snapshot.toDocument();
    }
    return parsed.document;
  }

  static bool _matchesWhisperTranscript(
    LyricDocument parsed,
    IndependentAsrTranscript snapshot,
  ) {
    if (parsed.language != snapshot.language ||
        (parsed.globalOffset ?? Duration.zero) !=
            (snapshot.globalOffset ?? Duration.zero) ||
        parsed.lines.length != snapshot.lines.length) {
      return false;
    }
    for (var index = 0; index < parsed.lines.length; index++) {
      final actual = parsed.lines[index];
      final saved = snapshot.lines[index];
      if (actual.id != saved.id ||
          actual.text != saved.text ||
          actual.startTime != saved.startTime ||
          actual.endTime != saved.endTime ||
          actual.isChorus != saved.isChorus ||
          actual.confidence != saved.confidence ||
          actual.confidenceSource != saved.confidenceSource) {
        return false;
      }
    }
    return true;
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
