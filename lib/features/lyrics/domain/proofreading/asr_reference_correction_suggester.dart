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
}

class AsrReferenceCorrectionSuggestion {
  final int draftIndex;
  final int referenceIndex;
  final String currentText;
  final String suggestedText;
  final double similarity;
  final AsrLineAlignmentStatus alignmentStatus;
  final Set<AsrReferenceCorrectionReason> reasons;

  AsrReferenceCorrectionSuggestion({
    required this.draftIndex,
    required this.referenceIndex,
    required this.currentText,
    required this.suggestedText,
    required this.similarity,
    required this.alignmentStatus,
    required Set<AsrReferenceCorrectionReason> reasons,
  }) : reasons = Set.unmodifiable(reasons);

  /// A text change must be re-timed before applying; no reference time is copied.
  bool get requiresRetiming => true;

  bool get requiresManualReview =>
      alignmentStatus != AsrLineAlignmentStatus.toBeCorrected ||
      reasons.contains(AsrReferenceCorrectionReason.structuralMismatch) ||
      reasons.contains(AsrReferenceCorrectionReason.referenceImportWarning);
}

class AsrReferenceCorrectionResult {
  final List<AsrReferenceCorrectionSuggestion> suggestions;
  AsrReferenceCorrectionResult({required List<AsrReferenceCorrectionSuggestion> suggestions})
    : suggestions = List.unmodifiable(suggestions);
}

/// Suggests text corrections for matched draft rows only. It never edits or
/// inserts lyrics, applies reference timestamps, or mutates the draft.
class AsrReferenceCorrectionSuggester {
  const AsrReferenceCorrectionSuggester();

  AsrReferenceCorrectionResult suggest({
    required LyricDocument draft,
    required ReferenceLyricInput reference,
    Set<int> protectedDraftIndices = const {},
    double suggestionThreshold = LyricAlignmentService.defaultAutoReplaceThreshold,
  }) {
    if (!suggestionThreshold.isFinite ||
        suggestionThreshold < 0 ||
        suggestionThreshold > 1) {
      throw ArgumentError.value(suggestionThreshold, 'suggestionThreshold');
    }
    if (protectedDraftIndices.any((i) => i < 0 || i >= draft.lines.length)) {
      throw ArgumentError.value(protectedDraftIndices, 'protectedDraftIndices');
    }

    final sanitized = const ReferenceTextSanitizer().sanitize(
      reference.lines.map((line) => line.text).join('\n'),
      title: reference.title,
      artist: reference.artist,
    );
    final removed = sanitized.removed.map((line) => line.originalIndex).toSet();
    final refs = <ReferenceLyricLine>[];
    final originalIndices = <int>[];
    var cleanIndex = 0;
    for (var i = 0; i < reference.lines.length; i++) {
      final line = reference.lines[i];
      if (removed.contains(i) || line.text.trim().isEmpty) continue;
      refs.add(ReferenceLyricLine(
        text: sanitized.lines[cleanIndex++],
        startTime: line.startTime,
        endTime: line.endTime,
      ));
      originalIndices.add(i);
    }
    if (refs.isEmpty) throw ArgumentError('Reference lyrics contain no usable lyric lines');

    final alignment = const LyricAlignmentService().align(
      document: draft,
      referenceLines: refs,
      autoReplaceThreshold: suggestionThreshold,
    );
    final warnings = [...reference.conflicts, ...reference.warnings];
    final suggestions = <AsrReferenceCorrectionSuggestion>[];
    for (final row in alignment.asrLines) {
      final refIndex = row.referenceIndex;
      if (refIndex == null ||
          row.status == AsrLineAlignmentStatus.matched ||
          row.status == AsrLineAlignmentStatus.unmatched ||
          protectedDraftIndices.contains(row.asrLineIndex)) {
        continue;
      }

      final current = draft.lines[row.asrLineIndex].text;
      final target = refs[refIndex].text;
      if (LyricAlignmentService.normalizeLine(current) ==
          LyricAlignmentService.normalizeLine(target)) continue;

      final reasons = <AsrReferenceCorrectionReason>{
        AsrReferenceCorrectionReason.textMismatch,
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
      if (warnings.isNotEmpty) {
        reasons.add(AsrReferenceCorrectionReason.referenceImportWarning);
      }

      suggestions.add(AsrReferenceCorrectionSuggestion(
        draftIndex: row.asrLineIndex,
        referenceIndex: originalIndices[refIndex],
        currentText: current,
        suggestedText: target,
        similarity: row.similarity,
        alignmentStatus: row.status,
        reasons: reasons,
      ));
    }

    return AsrReferenceCorrectionResult(suggestions: suggestions);
  }
}
