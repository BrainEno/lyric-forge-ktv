import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_alignment_service.dart';

enum AsrRetimingStatus {
  readyForReview, noTextChange, invalidProposedText, protectedLine,
  noMatchingEvidence, ambiguousEvidence, lowConfidenceEvidence,
  boundaryConflict, invalidTimingEvidence,
}

enum AsrRetimingReason {
  exactTimedTextMatch, splitAcrossEvidenceLines, textUnchanged,
  emptyProposedText, protectedLine, noExactNearbyMatch,
  multipleMatchingWindows, lowConfidence, overlapsPreviousLine,
  overlapsNextLine, negativeStart, nonPositiveDuration, durationTooShort,
  beyondAudioDuration, invalidOriginalTiming, invalidConfidenceEvidence,
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

  bool get canOfferForReview => status == AsrRetimingStatus.readyForReview;
}

/// Uses exact nearby secondary-ASR text/timing evidence; never mutates the draft
/// or estimates timestamps from text length.
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
  }) : assert(minimumTimingConfidence >= 0 && minimumTimingConfidence <= 100),
       assert(maxWindowLines > 0);

  AsrRetimingPlan plan({
    required LyricDocument draft,
    required int draftIndex,
    required String proposedText,
    required LyricDocument timingEvidence,
    Set<int> protectedDraftIndices = const {},
    Duration? audioDuration,
  }) {
    if (searchPadding.isNegative) {
      throw ArgumentError.value(
        searchPadding,
        'searchPadding',
        'Must be non-negative.',
      );
    }
    if (minimumDuration <= Duration.zero) {
      throw ArgumentError.value(
        minimumDuration,
        'minimumDuration',
        'Must be greater than zero.',
      );
    }
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

    if (timingEvidence.lines.any((line) => line.confidence < 0 || line.confidence > 100)) {
      return _result(
        draftIndex,
        proposedText,
        AsrRetimingStatus.invalidTimingEvidence,
        const [],
        {AsrRetimingReason.invalidConfidenceEvidence},
      );
    }

    final matches = <AsrRetimingOption>[];
    for (var start = 0; start < timingEvidence.lines.length; start++) {
      final window = <LyricLine>[];
      for (var length = 1; length <= maxWindowLines; length++) {
        final index = start + length - 1;
        if (index >= timingEvidence.lines.length) break;
        final line = timingEvidence.lines[index];
        if (line.startTime.isNegative || line.endTime <= line.startTime ||
            LyricAlignmentService.normalizeLine(line.text).isEmpty ||
            (window.isNotEmpty && line.startTime < window.last.startTime)) {
          break;
        }
        window.add(line);
        if (LyricAlignmentService.normalizeLine(window.map((x) => x.text).join(' ')) != requested) continue;

        var from = window.first.startTime;
        var to = window.first.endTime;
        var confidence = 0;
        for (final item in window) {
          if (item.startTime < from) from = item.startTime;
          if (item.endTime > to) to = item.endTime;
          confidence += item.confidence;
        }
        if (_gap(source.startTime, source.endTime, from, to) <= searchPadding) {
          matches.add(AsrRetimingOption(
            startTime: from, endTime: to,
            evidenceLineIndices: [for (var i = start; i < start + length; i++) i],
            meanConfidence: (confidence / window.length).round(),
          ));
        }
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

    final invalid = reasons.contains(AsrRetimingReason.negativeStart) ||
        reasons.contains(AsrRetimingReason.nonPositiveDuration) ||
        reasons.contains(AsrRetimingReason.durationTooShort) ||
        reasons.contains(AsrRetimingReason.beyondAudioDuration);
    final boundary = reasons.contains(AsrRetimingReason.overlapsPreviousLine) ||
        reasons.contains(AsrRetimingReason.overlapsNextLine);
    final status = invalid ? AsrRetimingStatus.invalidTimingEvidence
        : boundary ? AsrRetimingStatus.boundaryConflict
        : option.meanConfidence < minimumTimingConfidence
            ? AsrRetimingStatus.lowConfidenceEvidence
            : AsrRetimingStatus.readyForReview;
    return _result(draftIndex, proposedText, status, matches, reasons);
  }

  Duration _gap(Duration a, Duration b, Duration c, Duration d) {
    if (b < c) return c - b;
    if (d < a) return a - d;
    return Duration.zero;
  }

  AsrRetimingPlan _result(int index, String text, AsrRetimingStatus status,
      List<AsrRetimingOption> options, Set<AsrRetimingReason> reasons) =>
      AsrRetimingPlan(draftIndex: index, proposedText: text, status: status,
          options: options, reasons: reasons);
}
