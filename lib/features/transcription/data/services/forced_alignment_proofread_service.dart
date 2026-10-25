import 'dart:async';
import 'dart:io';

import '../../../lyrics/domain/proofreading/asr_first_pipeline.dart';
import '../../../lyrics/domain/proofreading/proofread_result.dart';
import '../../../project/domain/models/lyric_document.dart';
import 'forced_alignment_http_client.dart';

/// A safe boundary between the native arbitrary-text aligner and lyric review.
///
/// Alignment output is evidence only: this service never applies timestamps to
/// the source document. If the runtime is unavailable or returns invalid data,
/// callers still receive a normal review proposal plus a visible warning.
class ForcedAlignmentProofreadService {
  final ForcedAlignmentHttpClient client;
  final AsrFirstPipeline pipeline;

  const ForcedAlignmentProofreadService({
    required this.client,
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
      final spans = await client.align(
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
      );
      final matched = result.lines.where((line) => line.tokens.isNotEmpty).length;
      final warning = matched == draft.lines.length
          ? null
          : 'Forced alignment matched $matched of ${draft.lines.length} lyric lines; unmatched lines need manual review.';
      return ForcedAlignmentProofreadOutcome(
        result: result,
        alignmentAvailable: true,
        warning: warning,
      );
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
          notes: [
            ...result.notes,
            'forcedAlignmentUnavailable',
          ],
          referenceCoverage: result.referenceCoverage,
          autoFellBackToAsr: result.autoFellBackToAsr,
        ),
        alignmentAvailable: false,
        warning: 'Forced alignment is unavailable. Existing lyric text and timestamps were preserved; review timing manually.',
      );
    }
  }
}

/// Result of building a proposal with optional forced-alignment evidence.
class ForcedAlignmentProofreadOutcome {
  final ProofreadResult result;
  final bool alignmentAvailable;
  final String? warning;

  const ForcedAlignmentProofreadOutcome({
    required this.result,
    required this.alignmentAvailable,
    this.warning,
  });
}
