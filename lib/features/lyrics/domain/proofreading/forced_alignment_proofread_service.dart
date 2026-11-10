import '../../../project/domain/models/lyric_document.dart';
import 'asr_first_pipeline.dart';
import 'proofread_result.dart';

/// One timestamped text span returned by a forced-alignment backend.
class ForcedAlignedSpan {
  final String text;
  final Duration start;
  final Duration end;

  const ForcedAlignedSpan({
    required this.text,
    required this.start,
    required this.end,
  });
}

typedef ForcedAlignmentRunner =
    Future<List<ForcedAlignedSpan>> Function({
      required String audioPath,
      required String text,
      required String language,
      required Duration audioDuration,
    });

/// Alignment was not started because a cooperating ASR operation owns the
/// shared resource. Callers should let the user retry, not report bad setup.
class ForcedAlignmentResourceBusyException implements Exception {
  const ForcedAlignmentResourceBusyException();
}

/// A safe boundary between the native arbitrary-text aligner and lyric review.
///
/// Alignment output is evidence only: this service never applies timestamps to
/// the source document. If the runtime is unavailable or returns invalid data,
/// callers still receive a normal review proposal; presentation explains the
/// availability state using the result diagnostics.
class ForcedAlignmentProofreadService {
  final ForcedAlignmentRunner runner;
  final AsrFirstPipeline pipeline;

  const ForcedAlignmentProofreadService({
    required this.runner,
    this.pipeline = const AsrFirstPipeline(),
  });

  Future<ForcedAlignmentProofreadOutcome> buildReview({
    required LyricDocument draft,
    required String audioPath,
    required String referenceText,
    required String language,
    required Duration audioDuration,
    LyricDocument? secondary,
    Set<int> protectedDraftIndices = const {},
  }) async {
    try {
      final spans = await runner(
        audioPath: audioPath,
        text: referenceText,
        language: language,
        audioDuration: audioDuration,
      );
      final result = pipeline.build(
        draft: draft,
        secondary: secondary,
        protectedDraftIndices: protectedDraftIndices,
        audioDuration: audioDuration,
        forcedAlignmentSpans: [
          for (final span in spans)
            ProofreadAlignmentSpan(
              text: span.text,
              start: span.start,
              end: span.end,
            ),
        ],
        // An empty successful response is a real zero-coverage result, not
        // the same thing as alignment not being requested.
        forcedAlignmentRequested: true,
      );
      return ForcedAlignmentProofreadOutcome(
        result: result,
        alignmentAvailable: true,
      );
    } on ForcedAlignmentResourceBusyException {
      rethrow;
    } on Exception catch (_) {
      final result = pipeline.build(
        draft: draft,
        secondary: secondary,
        protectedDraftIndices: protectedDraftIndices,
        audioDuration: audioDuration,
      );
      return ForcedAlignmentProofreadOutcome(
        result: ProofreadResult(
          proposedDocument: result.proposedDocument,
          lines: result.lines,
          droppedLines: result.droppedLines,
          adlibs: result.adlibs,
          notes: [...result.notes, 'forcedAlignmentUnavailable'],
          referenceCoverage: result.referenceCoverage,
          autoFellBackToAsr: result.autoFellBackToAsr,
        ),
        alignmentAvailable: false,
      );
    }
  }
}

/// Result of building a proposal with optional forced-alignment evidence.
class ForcedAlignmentProofreadOutcome {
  final ProofreadResult result;
  final bool alignmentAvailable;

  const ForcedAlignmentProofreadOutcome({
    required this.result,
    required this.alignmentAvailable,
  });
}
