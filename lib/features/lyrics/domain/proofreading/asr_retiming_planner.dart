import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_alignment_service.dart';

enum AsrRetimingStatus {
  readyForReview,
  noTextChange,
  invalidProposedText,
  protectedLine,
  noMatchingEvidence,
  ambiguousEvidence,
  lowConfidenceEvidence,
  boundaryConflict,
  invalidTimingEvidence,
}

enum AsrRetimingReason {
  exactTimedTextMatch,
  splitAcrossEvidenceLines,
  textUnchanged,
  emptyProposedText,
  protectedLine,
  noExactNearbyMatch,
  multipleMatchingWindows,
  lowConfidence,
  overlapsPreviousLine,
  overlapsNextLine,
  negativeStart,
  nonPositiveDuration,
  durationTooShort,
  beyondAudioDuration,
  invalidOriginalTiming,
}

class AsrRetimingOption {
  final Duration startTime;
  final Duration endTime;
  final List<int> evidenceLineIndices;
  final int meanConfidence;

  AsrRetimingOption({
    required this.startTime,
    required this.endTime,
    required List<int> evidenceLineIndices,
    required this.meanConfidence,
  }) : evidenceLineIndices = List.unmodifiable(evidenceLineIndices);
}

class AsrRetimingPlan {
  final int draftIndex;
  final String proposedText;
  final AsrRetimingStatus status;
  final List<AsrRetimingOption> options;
  final Set<AsrRetimingReason> reasons;

  AsrRetimingPlan({
    required this.draftIndex,
    required this.proposedText,
    required this.status,
    required List<AsrRetimingOption> options,
    required Set<AsrRetimingReason> reasons,
  }) : options = List.unmodifiable(options),
       reasons = Set.unmodifiable(reasons);

  /// True means a unique, high-confidence interval is available for user review,
  /// not that it is automatically applied.
  bool get canOfferForReview => status == AsrRetimingStatus.readyForReview;
}

/// Finds exact text evidence in a nearby, timed secondary-ASR transcript.
/// It never derives timestamps from character count or mutates the draft.
class AsrRetimingPlanner {
  final Duration searchPadding;
  final Duration minimumDuration;
  final int minimumTimingConfidence;
  final int maxWindowLines;

  const AsrRetimingPlanner({
    this.searchPadding = const Duration(milliseconds: 1500),
    this.minimumDuration = const Duration(milliseconds: 300),
    this.minimumTimingConfidence = 70,
    this.maxWindowLines = 3,
  }) : assert(searchPadding >= Duration.zero),
       assert(minimumDuration > Duration.zero),
       assert(minimumTimingConfidence >= 0 && minimumTimingConfidence <= 100),
       assert(maxWindowLines > 0);

  AsrRetimingPlan plan({
    required LyricDocument draft,
    required int draftIndex,
    required String proposedText,
    required LyricDocument timingEvidence,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
  }) {
    if (draftIndex < 0 || draftIndex >= draft.lines.length ||
        protectedDraftIndices.any((i) => i < 0 || i >= draft.lines.length)) {
      throw ArgumentError('Draft or protected line index is out of range');
    }
    final source = draft.lines[draftIndex];
    final requested = LyricAlignmentService.normalizeLine(proposedText);
    if (protectedDraftIndices.contains(draftIndex)) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.protectedLine,
          const [], {AsrRetimingReason.protectedLine});
    }
    if (requested.isEmpty) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.invalidProposedText,
          const [], {AsrRetimingReason.emptyProposedText});
    }
    if (requested == LyricAlignmentService.normalizeLine(source.text)) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.noTextChange,
          const [], {AsrRetimingReason.textUnchanged});
    }
    if (source.startTime.isNegative || source.endTime <= source.startTime) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.invalidTimingEvidence,
          const [], {AsrRetimingReason.invalidOriginalTiming});
    }

    final matches = <AsrRetimingOption>[];
    for (var start = 0; start < timingEvidence.lines.length; start++) {
      final windowLines = <LyricLine>[];
      final indices = <int>[];
      for (var length = 1; length <= maxWindowLines; length++) {
        final index = start + length - 1;
        if (index >= timingEvidence.lines.length) break;
        final line = timingEvidence.lines[index];
        if (line.startTime.isNegative || line.endTime <= line.startTime ||
            LyricAlignmentService.normalizeLine(line.text).isEmpty) {
          break;
        }
        if (windowLines.isNotEmpty &&
            line.startTime < windowLines.last.startTime) {
          break;
        }
        windowLines.add(line);
        indices.add(index);
        final text = windowLines.map((item) => item.text).join(' ');
        if (LyricAlignmentService.normalizeLine(text) != requested) continue;

        var earliest = windowLines.first.startTime;
        var latest = windowLines.first.endTime;
        var confidenceTotal = 0;
        for (final item in windowLines) {
          if (item.startTime < earliest) earliest = item.startTime;
          if (item.endTime > latest) latest = item.endTime;
          confidenceTotal += item.confidence.clamp(0, 100);
        }
        if (_intervalGap(source.startTime, source.endTime, earliest, latest) >
            searchPadding) {
          continue;
        }
        matches.add(AsrRetimingOption(
          startTime: earliest,
          endTime: latest,
          evidenceLineIndices: indices,
          meanConfidence: (confidenceTotal / windowLines.length).round(),
        ));
      }
    }

    if (matches.isEmpty) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.noMatchingEvidence,
          const [], {AsrRetimingReason.noExactNearbyMatch});
    }
    if (matches.length > 1) {
      return _result(draftIndex, proposedText, AsrRetimingStatus.ambiguousEvidence,
          matches, {AsrRetimingReason.multipleMatchingWindows});
    }

    final option = matches.single;
    final reasons = <AsrRetimingReason>{
      option.evidenceLineIndices.length == 1
          ? AsrRetimingReason.exactTimedTextMatch
          : AsrRetimingReason.splitAcrossEvidenceLines,
    };
    if (option.startTime.isNegative) reasons.add(AsrRetimingReason.negativeStart);
    if (option.endTime <= option.startTime) {
      reasons.add(AsrRetimingReason.nonPositiveDuration);
    } else if (option.endTime - option.startTime < minimumDuration) {
      reasons.add(AsrRetimingReason.durationTooShort);
    }
    if (audioDuration != null &&
        (option.startTime >= audioDuration || option.endTime > audioDuration)) {
      reasons.add(AsrRetimingReason.beyondAudioDuration);
    }
    if (draftIndex > 0 && option.startTime < draft.lines[draftIndex - 1].endTime) {
      reasons.add(AsrRetimingReason.overlapsPreviousLine);
    }
    if (draftIndex + 1 < draft.lines.length &&
        option.endTime > draft.lines[draftIndex + 1].startTime) {
      reasons.add(AsrRetimingReason.overlapsNextLine);
    }
    if (option.meanConfidence < minimumTimingConfidence) {
      reasons.add(AsrRetimingReason.lowConfidence);
    }

    final invalidTiming = reasons.contains(AsrRetimingReason.negativeStart) ||
        reasons.contains(AsrRetimingReason.nonPositiveDuration) ||
        reasons.contains(AsrRetimingReason.durationTooShort) ||
        reasons.contains(AsrRetimingReason.beyondAudioDuration);
    final boundaryConflict = reasons.contains(AsrRetimingReason.overlapsPreviousLine) ||
        reasons.contains(AsrRetimingReason.overlapsNextLine);
    final status = invalidTiming
        ? AsrRetimingStatus.invalidTimingEvidence
        : boundaryConflict
        ? AsrRetimingStatus.boundaryConflict
        : option.meanConfidence < minimumTimingConfidence
        ? AsrRetimingStatus.lowConfidenceEvidence
        : AsrRetimingStatus.readyForReview;
    return _result(draftIndex, proposedText, status, matches, reasons);
  }

  Duration _intervalGap(Duration aStart, Duration aEnd, Duration bStart, Duration bEnd) {
    if (aEnd < bStart) return bStart - aEnd;
    if (bEnd < aStart) return aStart - bEnd;
    return Duration.zero;
  }

  AsrRetimingPlan _result(
    int draftIndex,
    String text,
    AsrRetimingStatus status,
    List<AsrRetimingOption> options,
    Set<AsrRetimingReason> reasons,
  ) => AsrRetimingPlan(
    draftIndex: draftIndex,
    proposedText: text,
    status: status,
    options: options,
    reasons: reasons,
  );
}
