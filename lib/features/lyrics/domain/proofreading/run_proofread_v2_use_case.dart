import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import '../services/lyric_review_decision_service.dart';
import 'asr_first_pipeline.dart';
import 'forced_alignment_language.dart';
import 'forced_alignment_proofread_service.dart';
import 'proofread_result.dart';
import 'proofread_review_proposal.dart';
import 'proofread_strategy_selector.dart';
import 'proofread_v2_review_assembler.dart';
import 'reference_first_pipeline.dart';
import 'reference_forced_alignment_planner.dart';
import 'reference_token_aligner.dart';

/// A forced-alignment request lacks a usable audio source or duration.
class ProofreadV2MissingAudioException implements Exception {
  const ProofreadV2MissingAudioException();
}

/// An uncommitted proposal and the structured information needed to review it.
class ProofreadV2RunResult {
  final ProofreadStrategyDecision decision;
  final ProofreadV2ReviewAssembly assembly;
  final LyricProofreadV2ReviewSummary summary;

  const ProofreadV2RunResult({
    required this.decision,
    required this.assembly,
    required this.summary,
  });
}

/// Builds a V2 proposal without mutating the draft or persisting any result.
///
/// The caller owns cancellation, editor revision checks, review, timeline
/// confirmation, and committing the accepted changes. Reference alignment is
/// separate review evidence and never changes proposed or accepted timestamps.
class RunProofreadV2UseCase {
  final ForcedAlignmentRunner runner;
  const RunProofreadV2UseCase({required this.runner});

  Future<ProofreadV2RunResult> build({
    required LyricDocument draft,
    required LyricSourceStrategy strategy,
    AudioAsset? audioAsset,
    ReferenceLyricInput? reference,
    LyricDocument? secondary,
    bool useForcedAlignment = false,
    Set<int> manuallyEditedIndices = const {},
  }) async {
    final coverage = reference == null
        ? null
        : const ReferenceTokenAligner()
              .align(
                referenceText: reference.lines
                    .map((line) => line.text)
                    .join(' '),
                draftText: draft.lines.map((line) => line.text).join(' '),
              )
              .referenceCoverage;
    final decision = const ProofreadStrategySelector().select(
      requestedStrategy: strategy,
      hasReference: reference != null,
      referenceCoverage: coverage,
    );
    final protectedIndices = <int>{
      ...manuallyEditedIndices,
      ...const LyricReviewDecisionService().reviewedIndices(draft),
    };
    const assembler = ProofreadV2ReviewAssembler();
    late final ProofreadV2ReviewAssembly assembly;
    if (decision.effectiveStrategy == LyricSourceStrategy.referenceFirst) {
      final result = const ReferenceFirstPipeline().build(
        draft: draft,
        reference: reference!,
        protectedDraftIndices: protectedIndices,
        audioDuration: audioAsset?.duration,
      );
      ReferenceForcedAlignmentPlan? referenceAlignmentPlan;
      if (useForcedAlignment) {
        final duration = audioAsset?.duration;
        if (audioAsset == null ||
            duration == null ||
            duration <= Duration.zero) {
          throw const ProofreadV2MissingAudioException();
        }
        final language = ForcedAlignmentLanguage.resolve(draft.language);
        referenceAlignmentPlan =
            await ReferenceForcedAlignmentService(runner: runner).build(
              reference: reference,
              audioPath: audioAsset.vocalPath ?? audioAsset.originalPath,
              language: language,
              audioDuration: duration,
            );
      }
      assembly = assembler.referenceFirst(
        draft: draft,
        requestedStrategy: strategy,
        requestedForcedAlignment: useForcedAlignment,
        referenceAlignmentPlan: referenceAlignmentPlan,
        hasSecondaryTranscript: secondary != null,
        result: result,
      );
    } else {
      ForcedAlignmentProofreadOutcome? alignmentOutcome;
      late final ProofreadResult result;
      if (useForcedAlignment) {
        final duration = audioAsset?.duration;
        if (audioAsset == null ||
            duration == null ||
            duration <= Duration.zero) {
          throw const ProofreadV2MissingAudioException();
        }
        final language = ForcedAlignmentLanguage.resolve(draft.language);
        alignmentOutcome = await ForcedAlignmentProofreadService(runner: runner)
            .buildReview(
              draft: draft,
              audioPath: audioAsset.vocalPath ?? audioAsset.originalPath,
              referenceText: draft.lines.map((line) => line.text).join('\n'),
              language: language,
              audioDuration: duration,
              secondary: secondary,
              protectedDraftIndices: protectedIndices,
            );
        result = alignmentOutcome.result;
      } else {
        result = const AsrFirstPipeline().build(
          draft: draft,
          secondary: secondary,
          protectedDraftIndices: protectedIndices,
          audioDuration: audioAsset?.duration,
        );
      }
      assembly = assembler.asrFirst(
        draft: draft,
        result: result,
        usedForcedAlignment: useForcedAlignment,
        hasSecondaryTranscript: secondary != null,
        autoFellBackToAsr: decision.autoFellBackToAsr,
        hasReference: reference != null,
        alignmentOutcome: alignmentOutcome,
      );
    }
    return ProofreadV2RunResult(
      decision: decision,
      assembly: assembly,
      summary: assembler.summary(
        effectiveStrategy: decision.effectiveStrategy,
        items: assembly.items,
        droppedItems: assembly.droppedItems,
        referenceCoverage: coverage,
      ),
    );
  }
}
