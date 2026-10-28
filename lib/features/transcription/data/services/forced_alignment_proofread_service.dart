import '../../../lyrics/domain/proofreading/asr_first_pipeline.dart';
import '../../../lyrics/domain/proofreading/proofread_result.dart';
import '../../../project/domain/models/lyric_document.dart';
import 'forced_alignment_http_client.dart';

typedef ForcedAlignmentRunner = Future<List<ForcedAlignedSpan>> Function({
  required String audioPath,
  required String text,
  required String language,
  required Duration audioDuration,
});

/// A safe boundary between the native arbitrary-text aligner and lyric review.
///
/// Alignment output is evidence only: this service never applies timestamps to
/// the source document. If the runtime is unavailable or returns invalid data,
/// callers still receive a normal review proposal plus a visible warning.
class ForcedAlignmentProofreadService {
  final ForcedAlignmentHttpClient? client;
  final ForcedAlignmentRunner? runner;
  final AsrFirstPipeline pipeline;

  const ForcedAlignmentProofreadService({
    this.client,
    this.runner,
    this.pipeline = const AsrFirstPipeline(),
  }) : assert(client != null || runner != null);

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
      final spans = runner != null
          ? await runner!(
              audioPath: audioPath,
              text: referenceText,
              language: language,
              audioDuration: audioDuration,
            )
          : await client!.align(
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
      final warning = _buildAlignmentWarning(result.alignmentDiagnostics);
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

  String? _buildAlignmentWarning(
    ProofreadAlignmentDiagnostics? diagnostics,
  ) {
    if (diagnostics == null) {
      return 'Forced alignment completed without line diagnostics; review timing manually.';
    }
    if (diagnostics.isComplete) return null;

    final coveragePercent = (diagnostics.lineCoverage * 100).round();
    final details = <String>[
      'Forced alignment matched ${diagnostics.matchedLineCount} of '
          '${diagnostics.totalLineCount} lyric lines '
          '($coveragePercent% coverage).',
    ];
    if (diagnostics.hasSkippedSpans) {
      details.add('Skipped alignment spans: ${diagnostics.skippedSpanCount}.');
    }
    if (diagnostics.hasUnmatchedLines) {
      details.add(
        'Unmatched lyric lines: ${diagnostics.unmatchedLineNumbers.join(', ')}.',
      );
    }
    details.add(
      'Review alignment evidence manually; no lyric timestamps were changed.',
    );
    return details.join(' ');
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
