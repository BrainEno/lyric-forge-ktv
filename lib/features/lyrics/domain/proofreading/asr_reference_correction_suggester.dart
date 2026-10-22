import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_input.dart';
import '../models/reference_lyric_line.dart';
import '../services/lyric_alignment_service.dart';
import 'reference_text_sanitizer.dart';

enum AsrReferenceCorrectionReason {
  textMismatch,
  lowAlignmentConfidence,
  ambiguousAlignment,
  structuralMismatch,
  referenceImportWarning,
  timingReviewRequired,
}

class AsrReferenceCorrectionSuggestion {
  final int draftIndex;
  final int referenceIndex;
  final String currentText;
  final String suggestedText;
  final double similarity;
  final int draftConfidence;
  final AsrLineAlignmentStatus alignmentStatus;
  final bool referenceHasTimestamp;
  final Set<AsrReferenceCorrectionReason> reasons;

  AsrReferenceCorrectionSuggestion({
    required this.draftIndex,
    required this.referenceIndex,
    required this.currentText,
    required this.suggestedText,
    required this.similarity,
    required this.draftConfidence,
    required this.alignmentStatus,
    required this.referenceHasTimestamp,
    required Set<AsrReferenceCorrectionReason> reasons,
  }) : reasons = Set.unmodifiable(reasons);

  /// Text changes must be re-timed before they can be applied.
  bool get requiresRetiming =>
      reasons.contains(AsrReferenceCorrectionReason.timingReviewRequired);

  bool get requiresManualReview =>
      alignmentStatus != AsrLineAlignmentStatus.toBeCorrected ||
      reasons.contains(AsrReferenceCorrectionReason.structuralMismatch) ||
      reasons.contains(AsrReferenceCorrectionReason.referenceImportWarning);
}

class AsrReferenceCorrectionResult {
  final List<AsrReferenceCorrectionSuggestion> suggestions;
  final List<int> missingReferenceIndices;
  final List<RemovedLine> removedReferenceLines;
  final List<String> warnings;

  AsrReferenceCorrectionResult({
    required List<AsrReferenceCorrectionSuggestion> suggestions,
    required List<int> missingReferenceIndices,
    required List<RemovedLine> removedReferenceLines,
    required List<String> warnings,
  }) : suggestions = List.unmodifiable(suggestions),
       missingReferenceIndices = List.unmodifiable(missingReferenceIndices),
       removedReferenceLines = List.unmodifiable(removedReferenceLines),
       warnings = List.unmodifiable(warnings);
}

/// Produces reference-text suggestions for existing ASR rows only.
///
/// It never applies reference text or reference timestamps, inserts missed
/// lyrics, or mutates the draft. Suggested text changes require re-timing.
class AsrReferenceCorrectionSuggester {
  final ReferenceTextSanitizer sanitizer;
  final LyricAlignmentService lineAligner;

  const AsrReferenceCorrectionSuggester({
    this.sanitizer = const ReferenceTextSanitizer(),
    this.lineAligner = const LyricAlignmentService(),
  });

  AsrReferenceCorrectionResult suggest({
    required LyricDocument draft,
    required ReferenceLyricInput reference,
    Set<int> protectedDraftIndices = const {},
    double suggestionThreshold =
        LyricAlignmentService.defaultAutoReplaceThreshold,
  }) {
    if (!suggestionThreshold.isFinite ||
        suggestionThreshold < 0 ||
        suggestionThreshold > 1) {
      throw ArgumentError.value(suggestionThreshold, 'suggestionThreshold');
    }
    if (protectedDraftIndices.any(
      (index) => index < 0 || index >= draft.lines.length,
    )) {
      throw ArgumentError.value(protectedDraftIndices, 'protectedDraftIndices');
    }

    final sanitized = sanitizer.sanitize(
      reference.lines.map((line) => line.text).join('\n'),
      title: reference.title,
      artist: reference.artist,
    );
    final removedIndices = sanitized.removed.map((line) => line.originalIndex).toSet();
    final cleanedLines = <ReferenceLyricLine>[];
    final originalIndices = <int>[];
    var cleanIndex = 0;
    for (var index = 0; index < reference.lines.length; index++) {
      final source = reference.lines[index];
      if (removedIndices.contains(index) || source.text.trim().isEmpty) continue;
      cleanedLines.add(
        ReferenceLyricLine(
          text: sanitized.lines[cleanIndex++],
          startTime: source.startTime,
          endTime: source.endTime,
        ),
      );
      originalIndices.add(index);
    }
    if (cleanedLines.isEmpty) {
      throw ArgumentError('Reference lyrics contain no usable lyric lines');
    }

    final alignment = lineAligner.align(
      document: draft,
      referenceLines: cleanedLines,
      autoReplaceThreshold: suggestionThreshold,
    );
    final importWarnings = [...reference.conflicts, ...reference.warnings];
    final suggestions = <AsrReferenceCorrectionSuggestion>[];
    for (final row in alignment.asrLines) {
      final referenceIndex = row.referenceIndex;
      if (referenceIndex == null ||
          row.status == AsrLineAlignmentStatus.matched ||
          row.status == AsrLineAlignmentStatus.unmatched ||
          protectedDraftIndices.contains(row.asrLineIndex)) {
        continue;
      }

      final current = draft.lines[row.asrLineIndex];
      final target = cleanedLines[referenceIndex];
      if (LyricAlignmentService.normalizeLine(current.text) ==
          LyricAlignmentService.normalizeLine(target.text)) {
        continue;
      }

      final reasons = <AsrReferenceCorrectionReason>{
        AsrReferenceCorrectionReason.textMismatch,
        AsrReferenceCorrectionReason.timingReviewRequired,
      };
      if (row.status == AsrLineAlignmentStatus.lowConfidence) {
        reasons.add(AsrReferenceCorrectionReason.lowAlignmentConfidence);
      }
      if (row.status == AsrLineAlignmentStatus.ambiguous || row.ambiguous) {
        reasons.add(AsrReferenceCorrectionReason.ambiguousAlignment);
      }
      if (row.structuralMismatch) {
        reasons.add(AsrReferenceCorrectionReason.structuralMismatch);
      }
      if (importWarnings.isNotEmpty) {
        reasons.add(AsrReferenceCorrectionReason.referenceImportWarning);
      }

      suggestions.add(
        AsrReferenceCorrectionSuggestion(
          draftIndex: row.asrLineIndex,
          referenceIndex: originalIndices[referenceIndex],
          currentText: current.text,
          suggestedText: target.text,
          similarity: row.similarity,
          draftConfidence: current.confidence,
          alignmentStatus: row.status,
          referenceHasTimestamp: target.hasTimestamp,
          reasons: reasons,
        ),
      );
    }

    return AsrReferenceCorrectionResult(
      suggestions: suggestions,
      missingReferenceIndices: [
        for (final index in alignment.missingReferenceIndices)
          originalIndices[index],
      ],
      removedReferenceLines: sanitized.removed,
      warnings: importWarnings,
    );
  }
}
