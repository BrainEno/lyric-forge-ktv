import '../../../project/domain/models/lyric_document.dart';
import 'lyric_review_decision_service.dart';
import 'lyric_timeline_validator.dart';

enum LyricReviewRiskLevel { low, medium, high, critical }

/// One explainable, non-probabilistic priority score for a lyric row.
///
/// The score is a sorting aid, not a claim that the lyric is wrong. Signals and
/// reasons stay separate so the UI can explain why a row was surfaced.
class LyricReviewPriority {
  final int lineIndex;
  final int score;
  final List<String> reasons;

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
        score.add(60, '歌词为空');
      }

      if (line.confidence <= 25) {
        score.add(38, '识别置信度极低（${line.confidence}）');
      } else if (line.confidence <= 45) {
        score.add(30, '识别置信度很低（${line.confidence}）');
      } else if (line.confidence <= 60) {
        score.add(23, '识别置信度偏低（${line.confidence}）');
      } else if (line.confidence < 70) {
        score.add(16, '识别置信度低于复核阈值（${line.confidence}）');
      }

      if (line.confidence < 100) {
        final candidate = candidates[index];
        if (candidate != null && _hasEngineDisagreement(line.text, candidate)) {
          final similarity = _number(candidate['similarity']);
          if (similarity != null && similarity < 0.50) {
            score.add(30, '双引擎结果差异很大');
          } else if (similarity != null && similarity < 0.72) {
            score.add(23, '双引擎结果存在明显分歧');
          } else {
            score.add(15, '双引擎存在不同候选');
          }
        }
      }

      if (line.confidence < 95 &&
          text.isNotEmpty &&
          RegExp(r'(\S{1,24})(?:\s+\1){2,}', caseSensitive: false)
              .hasMatch(text)) {
        score.add(12, '出现连续重复词，建议确认是否为识别重复');
      }

      if (text.runes.length > 90) {
        score.add(10, '单行文本异常偏长，可能包含多句歌词');
      }

      final duration = line.endTime - line.startTime;
      if (text.runes.length >= 4 &&
          duration > Duration.zero &&
          duration < const Duration(milliseconds: 180)) {
        score.add(18, '歌词文本较长但显示区间极短');
      } else if (duration > const Duration(seconds: 20)) {
        score.add(12, '单行持续时间超过 20 秒');
      }

      for (final issue in issuesByLine[index] ?? const <TimelineIssue>[]) {
        final weight = _timelineIssueWeight(issue.type);
        if (weight > 0) score.add(weight, _timelineIssueLabel(issue));
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

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

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

  String _timelineIssueLabel(TimelineIssue issue) => switch (issue.type) {
    TimelineIssueType.negativeStart => '开始时间为负',
    TimelineIssueType.negativeEffectiveStart => '叠加全局偏移后开始时间为负',
    TimelineIssueType.zeroOrNegativeDuration => '歌词时间区间无效',
    TimelineIssueType.nonMonotonicStart => '歌词顺序与时间顺序不一致',
    TimelineIssueType.duplicateStart => '与上一行开始时间重复',
    TimelineIssueType.overlapsPrevious => '与上一行时间重叠',
    TimelineIssueType.overlapsNext => '与下一行时间重叠',
    TimelineIssueType.extremelyShortGap => '与下一行之间的间隔极短',
    TimelineIssueType.beyondAudioDuration => '开始时间超出音频长度',
    TimelineIssueType.endBeyondAudioDuration => '结束时间超出音频长度',
  };
}

class _PriorityAccumulator {
  int value = 0;
  final List<String> reasons = [];

  void add(int points, String reason) {
    value = (value + points).clamp(0, 100).toInt();
    if (!reasons.contains(reason)) reasons.add(reason);
  }
}
