import '../../../project/domain/models/lyric_document.dart';
import 'lyric_review_decision_service.dart';
import 'lyric_timeline_validator.dart';

enum LyricReviewRiskLevel { low, medium, high, critical }

enum LyricReviewPriorityReasonCode {
  emptyLyrics,
  confidenceExtremelyLow,
  confidenceVeryLow,
  confidenceLow,
  confidenceBelowThreshold,
  enginesDifferGreatly,
  enginesDifferClearly,
  enginesHaveDifferentCandidates,
  repeatedWords,
  unusuallyLongText,
  longTextWithShortInterval,
  intervalOverTwentySeconds,
  negativeStart,
  negativeEffectiveStart,
  invalidTimeInterval,
  nonMonotonicStart,
  duplicateStart,
  overlapsPrevious,
  overlapsNext,
  extremelyShortGap,
  startBeyondAudio,
  endBeyondAudio,
}

/// A stable reason code plus the confidence value used by confidence reasons.
class LyricReviewPriorityReason {
  final LyricReviewPriorityReasonCode code;
  final int? confidence;

  const LyricReviewPriorityReason(this.code, {this.confidence});

  @override
  bool operator ==(Object other) =>
      other is LyricReviewPriorityReason &&
      other.code == code &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(code, confidence);
}

/// One explainable, non-probabilistic priority score for a lyric row.
///
/// The score is a sorting aid, not a claim that the lyric is wrong. Signals and
/// reason codes stay separate so the UI can explain why a row was surfaced.
class LyricReviewPriority {
  final int lineIndex;
  final int score;
  final List<LyricReviewPriorityReason> reasons;

  const LyricReviewPriority({
    required this.lineIndex,
    required this.score,
    required this.reasons,
  });

  LyricReviewRiskLevel get level => switch (score) {
    >= 65 => LyricReviewRiskLevel.critical,
    >= 45 => LyricReviewRiskLevel.high,
    >= 25 => LyricReviewRiskLevel.medium,
    _ => LyricReviewRiskLevel.low,
  };
}

/// Builds a small review queue from local ASR evidence already present in the
/// document. It does not call a model, edit text, or change timestamps.
class LyricReviewPriorityService {
  static const int minimumQueueScore = 12;

  final LyricTimelineValidator timelineValidator;
  final LyricReviewDecisionService reviewDecisionService;

  const LyricReviewPriorityService({
    this.timelineValidator = const LyricTimelineValidator(),
    this.reviewDecisionService = const LyricReviewDecisionService(),
  });

  List<LyricReviewPriority> rank(
    LyricDocument document, {
    Duration? audioDuration,
  }) {
    if (document.lines.isEmpty) return const [];

    final reviewedIndices = reviewDecisionService.reviewedIndices(document);
    final candidates = _fallbackCandidatesByIndex(document.metadata);
    final timeline = timelineValidator.validate(
      lines: document.lines,
      audioDuration: audioDuration,
      globalOffset: document.globalOffset ?? Duration.zero,
    );
    final issuesByLine = <int, List<TimelineIssue>>{};
    for (final issue in timeline.issues) {
      issuesByLine.putIfAbsent(issue.lineIndex, () => []).add(issue);
    }

    final ranked = <LyricReviewPriority>[];
    for (var index = 0; index < document.lines.length; index++) {
      if (reviewedIndices.contains(index)) continue;
      final line = document.lines[index];
      final score = _PriorityAccumulator();
      final text = line.text.trim();

      if (text.isEmpty) {
        score.add(60, LyricReviewPriorityReasonCode.emptyLyrics);
      }

      // Unscored lines carry a placeholder number, not a model score, so the
      // confidence ladder must not rank them as if the engine had been unsure.
      if (line.hasConfidenceScore) {
        if (line.confidence <= 25) {
          score.add(
            38,
            LyricReviewPriorityReasonCode.confidenceExtremelyLow,
            confidence: line.confidence,
          );
        } else if (line.confidence <= 45) {
          score.add(
            30,
            LyricReviewPriorityReasonCode.confidenceVeryLow,
            confidence: line.confidence,
          );
        } else if (line.confidence <= 60) {
          score.add(
            23,
            LyricReviewPriorityReasonCode.confidenceLow,
            confidence: line.confidence,
          );
        } else if (line.confidence < 70) {
          score.add(
            16,
            LyricReviewPriorityReasonCode.confidenceBelowThreshold,
            confidence: line.confidence,
          );
        }
      }

      if (line.confidence < 100) {
        final candidate = candidates[index];
        if (candidate != null && _hasEngineDisagreement(line.text, candidate)) {
          final similarity = _number(candidate['similarity']);
          if (similarity != null && similarity < 0.50) {
            score.add(30, LyricReviewPriorityReasonCode.enginesDifferGreatly);
          } else if (similarity != null && similarity < 0.72) {
            score.add(23, LyricReviewPriorityReasonCode.enginesDifferClearly);
          } else {
            score.add(
              15,
              LyricReviewPriorityReasonCode.enginesHaveDifferentCandidates,
            );
          }
        }
      }

      if (line.confidence < 95 &&
          text.isNotEmpty &&
          RegExp(
            r'(\S{1,24})(?:\s+\1){2,}',
            caseSensitive: false,
          ).hasMatch(text)) {
        score.add(12, LyricReviewPriorityReasonCode.repeatedWords);
      }

      if (text.runes.length > 90) {
        score.add(10, LyricReviewPriorityReasonCode.unusuallyLongText);
      }

      final duration = line.endTime - line.startTime;
      if (text.runes.length >= 4 &&
          duration > Duration.zero &&
          duration < const Duration(milliseconds: 180)) {
        score.add(18, LyricReviewPriorityReasonCode.longTextWithShortInterval);
      } else if (duration > const Duration(seconds: 20)) {
        score.add(12, LyricReviewPriorityReasonCode.intervalOverTwentySeconds);
      }

      for (final issue in issuesByLine[index] ?? const <TimelineIssue>[]) {
        final weight = _timelineIssueWeight(issue.type);
        if (weight > 0) {
          score.add(weight, _timelineIssueReason(issue.type));
        }
      }

      if (score.value >= minimumQueueScore) {
        ranked.add(
          LyricReviewPriority(
            lineIndex: index,
            score: score.value,
            reasons: List.unmodifiable(score.reasons),
          ),
        );
      }
    }

    ranked.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      return byScore != 0 ? byScore : left.lineIndex.compareTo(right.lineIndex);
    });
    return List.unmodifiable(ranked);
  }

  Map<int, Map<String, dynamic>> _fallbackCandidatesByIndex(
    Map<String, dynamic> metadata,
  ) {
    final raw = metadata['fallbackCandidates'];
    if (raw is! List) return const {};
    final result = <int, Map<String, dynamic>>{};
    for (final value in raw) {
      if (value is! Map) continue;
      final candidate = Map<String, dynamic>.from(value);
      final index = candidate['lineIndex'];
      if (index is num && index >= 0) {
        result[index.toInt()] = candidate;
      }
    }
    return result;
  }

  bool _hasEngineDisagreement(
    String currentText,
    Map<String, dynamic> candidate,
  ) {
    final primary = _firstText(candidate, const [
      'primaryText',
      'whisperText',
      'qwenText',
    ]);
    final alternative = _firstAlternativeText(candidate, primary);
    if (primary == null || alternative == null) return false;

    final normalizedPrimary = _normalize(primary);
    final normalizedAlternative = _normalize(alternative);
    if (normalizedPrimary.isEmpty || normalizedAlternative.isEmpty) {
      return false;
    }
    if (normalizedPrimary == normalizedAlternative) return false;

    // Keep a disagreement surfaced even when the merge already selected the
    // alternate candidate: its confidence remains below 100 until reviewed.
    return _normalize(currentText).isNotEmpty;
  }

  String? _firstText(Map<String, dynamic> candidate, List<String> keys) {
    for (final key in keys) {
      final value = candidate[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _firstAlternativeText(
    Map<String, dynamic> candidate,
    String? primary,
  ) {
    final explicit = candidate['alternativeText']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final primaryEngine = candidate['primaryEngine']?.toString();
    final possibleKeys = primaryEngine == 'whisper'
        ? const ['qwenText', 'whisperText']
        : const ['whisperText', 'qwenText'];
    for (final key in possibleKeys) {
      final value = candidate[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != primary) return value;
    }
    return null;
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int _timelineIssueWeight(TimelineIssueType type) => switch (type) {
    TimelineIssueType.negativeStart => 32,
    TimelineIssueType.negativeEffectiveStart => 22,
    TimelineIssueType.zeroOrNegativeDuration => 42,
    TimelineIssueType.nonMonotonicStart => 42,
    TimelineIssueType.duplicateStart => 36,
    TimelineIssueType.overlapsPrevious => 28,
    TimelineIssueType.overlapsNext => 26,
    TimelineIssueType.extremelyShortGap => 10,
    TimelineIssueType.beyondAudioDuration => 42,
    TimelineIssueType.endBeyondAudioDuration => 16,
  };

  LyricReviewPriorityReasonCode _timelineIssueReason(TimelineIssueType type) =>
      switch (type) {
        TimelineIssueType.negativeStart =>
          LyricReviewPriorityReasonCode.negativeStart,
        TimelineIssueType.negativeEffectiveStart =>
          LyricReviewPriorityReasonCode.negativeEffectiveStart,
        TimelineIssueType.zeroOrNegativeDuration =>
          LyricReviewPriorityReasonCode.invalidTimeInterval,
        TimelineIssueType.nonMonotonicStart =>
          LyricReviewPriorityReasonCode.nonMonotonicStart,
        TimelineIssueType.duplicateStart =>
          LyricReviewPriorityReasonCode.duplicateStart,
        TimelineIssueType.overlapsPrevious =>
          LyricReviewPriorityReasonCode.overlapsPrevious,
        TimelineIssueType.overlapsNext =>
          LyricReviewPriorityReasonCode.overlapsNext,
        TimelineIssueType.extremelyShortGap =>
          LyricReviewPriorityReasonCode.extremelyShortGap,
        TimelineIssueType.beyondAudioDuration =>
          LyricReviewPriorityReasonCode.startBeyondAudio,
        TimelineIssueType.endBeyondAudioDuration =>
          LyricReviewPriorityReasonCode.endBeyondAudio,
      };
}

class _PriorityAccumulator {
  int value = 0;
  final List<LyricReviewPriorityReason> reasons = [];

  void add(int points, LyricReviewPriorityReasonCode code, {int? confidence}) {
    value = (value + points).clamp(0, 100).toInt();
    final reason = LyricReviewPriorityReason(code, confidence: confidence);
    if (!reasons.contains(reason)) reasons.add(reason);
  }
}
