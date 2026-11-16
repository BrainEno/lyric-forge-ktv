import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_line_structure_service.dart';
import 'lyric_timeline_validator.dart';

/// Why a row's timing is offered for repair.
enum LyricTimelineFixReason {
  /// The start time is before 0:00 and is moved to 0:00.
  negativeStart,

  /// The start is out of lyric order (earlier than, or equal to, the row
  /// above) and this row is the one that breaks the order; it is re-slotted
  /// between its neighbours.
  outOfOrder,

  /// The end is not after the start; the end is estimated from the text.
  zeroDuration,

  /// The end runs into the next row's start; it is trimmed to that start.
  overlapsNext,

  /// A gap to the next row too short to be a pause; the end is extended to
  /// the next start so the display does not flicker.
  shortGap,

  /// The end runs past the end of the audio; it is clipped to the audio end.
  pastAudioEnd,
}

/// One row whose timing the planner would change.
///
/// A row can collect several reasons (for example re-slotted, then trimmed
/// against its neighbour); [after] is the combined result.
class LyricTimelineFix {
  final int index;
  final LyricLine before;
  final LyricLine after;
  final Set<LyricTimelineFixReason> reasons;

  const LyricTimelineFix({
    required this.index,
    required this.before,
    required this.after,
    required this.reasons,
  });

  /// Re-slotting a row is a judgement about which row is wrong; the other
  /// repairs follow mechanically from the neighbouring timestamps.
  bool get confident => !reasons.contains(LyricTimelineFixReason.outOfOrder);

  bool get movesStart => before.startTime != after.startTime;
}

/// A timeline problem the planner cannot fix by rule.
class LyricTimelineManualIssue {
  final int index;
  final String message;

  const LyricTimelineManualIssue({required this.index, required this.message});
}

/// The result of [LyricTimelineRepairPlanner.plan].
class LyricTimelineRepairPlan {
  /// One entry per changed row, in row order.
  final List<LyricTimelineFix> fixes;

  /// Problems that remain even when every fix is applied.
  final List<LyricTimelineManualIssue> manualIssues;

  /// Rows with timeline problems that were left alone because they were
  /// edited by hand.
  final Set<int> skippedProtectedIndices;

  const LyricTimelineRepairPlan({
    required this.fixes,
    required this.manualIssues,
    required this.skippedProtectedIndices,
  });

  static const LyricTimelineRepairPlan empty = LyricTimelineRepairPlan(
    fixes: [],
    manualIssues: [],
    skippedProtectedIndices: {},
  );

  bool get isEmpty => fixes.isEmpty;

  /// Rows the user has to look at: fixable rows plus manual issues.
  int get problemRowCount =>
      {...fixes.map((f) => f.index), ...manualIssues.map((i) => i.index)}.length;

  /// [document] with the fixes at [selectedPositions] (indices into
  /// [fixes]) applied. Repaired rows with a stable id are recorded as
  /// [LyricTimingProvenance.autoRepaired] so later tools can tell their
  /// timing was adjusted by rule.
  LyricDocument applyTo(LyricDocument document, Set<int> selectedPositions) {
    if (selectedPositions.isEmpty) return document;
    final lines = List<LyricLine>.from(document.lines);
    final provenance = <String, Object?>{
      ...?_asStringMap(document.metadata[kLyricTimingProvenanceKey]),
    };
    var changed = false;
    for (final position in selectedPositions.toList()..sort()) {
      if (position < 0 || position >= fixes.length) continue;
      final fix = fixes[position];
      if (fix.index >= lines.length) continue;
      final current = lines[fix.index];
      lines[fix.index] = current.copyWith(
        startTime: fix.after.startTime,
        endTime: fix.after.endTime,
      );
      final id = current.id;
      if (id != null) {
        provenance[id] = LyricTimingProvenance.autoRepaired.name;
      }
      changed = true;
    }
    if (!changed) return document;
    return document.copyWith(
      lines: lines,
      metadata: provenance.isEmpty
          ? document.metadata
          : {...document.metadata, kLyricTimingProvenanceKey: provenance},
    );
  }

  /// The first repaired row, so the editor can show where the work happened.
  int? selectionAfterApply(Set<int> selectedPositions) {
    int? first;
    for (final position in selectedPositions) {
      if (position < 0 || position >= fixes.length) continue;
      final index = fixes[position].index;
      if (first == null || index < first) first = index;
    }
    return first;
  }

  static Map<String, Object?>? _asStringMap(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}

/// Plans deterministic timing repairs for a whole document.
///
/// Recognised drafts and hand-timed rows accumulate small timeline faults:
/// rows overlapping the next one, an end left before its start, a tail
/// running past the audio, a row whose start was typed wrong and now sits
/// out of lyric order. The validator already reports them row by row; this
/// planner turns them into a reviewable set of repairs:
///
/// * a start before 0:00 moves to 0:00;
/// * an out-of-order row is re-slotted after the row above, but only when
///   it is clearly that row (removing it restores the order of its
///   neighbours, and removing the neighbour would not); such repairs are
///   marked not [LyricTimelineFix.confident];
/// * a zero or negative duration gets an end estimated from the sung text
///   (0.35 s per sung unit, 1–6 s), never past the next start;
/// * an end running into the next start is trimmed to it;
/// * a gap shorter than [shortGap] is closed;
/// * an end past the audio is clipped to the audio end.
///
/// Lyric text and row order are never changed, no repair leaves a row
/// shorter than [minimumDuration], and rows in `protectedIndices` (hand
/// edited) are never moved; their problems are reported instead.
class LyricTimelineRepairPlanner {
  const LyricTimelineRepairPlanner({
    this.validator = const LyricTimelineValidator(),
    this.structure = const LyricLineStructureService(),
  });

  final LyricTimelineValidator validator;
  final LyricLineStructureService structure;

  /// No repair produces a row shorter than this.
  static const Duration minimumDuration = Duration(milliseconds: 200);

  /// Gaps shorter than this are closed (matches the validator's threshold).
  static const Duration shortGap = LyricTimelineValidator.defaultMinGap;

  static const Duration _perSungUnit = Duration(milliseconds: 350);
  static const Duration _estimateMin = Duration(seconds: 1);
  static const Duration _estimateMax = Duration(seconds: 6);

  LyricTimelineRepairPlan plan(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
    Duration? audioDuration,
  }) {
    final original = document.lines;
    if (original.isEmpty) return LyricTimelineRepairPlan.empty;

    final lines = List<LyricLine>.from(original);
    final reasons = <int, Set<LyricTimelineFixReason>>{};
    bool editable(int index) => !protectedIndices.contains(index);

    void change(int index, LyricLine next, LyricTimelineFixReason reason) {
      final current = lines[index];
      if (current.startTime == next.startTime &&
          current.endTime == next.endTime) {
        return;
      }
      lines[index] = next;
      reasons.putIfAbsent(index, () => {}).add(reason);
    }

    // 1. Starts before 0:00.
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!line.startTime.isNegative || !editable(index)) continue;
      var end = line.endTime;
      if (end < minimumDuration) {
        end = _boundedEnd(lines, index, Duration.zero, audioDuration);
      }
      if (end - Duration.zero < minimumDuration) continue;
      change(
        index,
        line.copyWith(startTime: Duration.zero, endTime: end),
        LyricTimelineFixReason.negativeStart,
      );
    }

    // 2. Rows out of lyric order.
    for (var index = 1; index < lines.length; index++) {
      if (lines[index].startTime > lines[index - 1].startTime) continue;
      final culprit = _culprit(lines, index - 1, index);
      if (culprit == null || !editable(culprit)) continue;
      final slot = _slotFor(lines, culprit, audioDuration);
      if (slot == null) continue;
      change(
        culprit,
        lines[culprit].copyWith(startTime: slot.$1, endTime: slot.$2),
        LyricTimelineFixReason.outOfOrder,
      );
    }

    // 3. Zero or negative durations.
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.endTime > line.startTime || !editable(index)) continue;
      if (line.startTime.isNegative) continue;
      final end = _boundedEnd(lines, index, line.startTime, audioDuration);
      if (end - line.startTime < minimumDuration) continue;
      change(
        index,
        line.copyWith(endTime: end),
        LyricTimelineFixReason.zeroDuration,
      );
    }

    // 4. Overlaps with the next row, then 5. hairline gaps.
    for (var index = 0; index < lines.length - 1; index++) {
      if (!editable(index)) continue;
      final line = lines[index];
      final next = lines[index + 1];
      if (next.startTime <= line.startTime) continue;
      if (line.endTime > next.startTime) {
        if (next.startTime - line.startTime < minimumDuration) continue;
        change(
          index,
          line.copyWith(endTime: next.startTime),
          LyricTimelineFixReason.overlapsNext,
        );
      } else {
        final gap = next.startTime - line.endTime;
        if (gap > Duration.zero && gap < shortGap) {
          change(
            index,
            line.copyWith(endTime: next.startTime),
            LyricTimelineFixReason.shortGap,
          );
        }
      }
    }

    // 6. Tails running past the audio.
    if (audioDuration != null && audioDuration > Duration.zero) {
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (!editable(index) ||
            line.endTime <= audioDuration ||
            audioDuration - line.startTime < minimumDuration) {
          continue;
        }
        change(
          index,
          line.copyWith(endTime: audioDuration),
          LyricTimelineFixReason.pastAudioEnd,
        );
      }
    }

    final fixes = <LyricTimelineFix>[
      for (final index in reasons.keys.toList()..sort())
        if (original[index].startTime != lines[index].startTime ||
            original[index].endTime != lines[index].endTime)
          LyricTimelineFix(
            index: index,
            before: original[index],
            after: lines[index],
            reasons: Set.unmodifiable(reasons[index]!),
          ),
    ];

    final remaining = validator.validate(
      lines: lines,
      audioDuration: audioDuration,
    );
    final manual = <LyricTimelineManualIssue>[];
    final skipped = <int>{};
    final seen = <int>{};
    for (final issue in remaining.issues) {
      // A hairline gap is cosmetic; it is not worth a manual-review entry.
      if (issue.type == TimelineIssueType.extremelyShortGap) continue;
      if (protectedIndices.contains(issue.lineIndex)) {
        skipped.add(issue.lineIndex);
        continue;
      }
      if (!seen.add(issue.lineIndex)) continue;
      manual.add(
        LyricTimelineManualIssue(
          index: issue.lineIndex,
          message: issue.message,
        ),
      );
    }

    return LyricTimelineRepairPlan(
      fixes: List.unmodifiable(fixes),
      manualIssues: List.unmodifiable(manual),
      skippedProtectedIndices: Set.unmodifiable(skipped),
    );
  }

  /// Timeline problems that remain after applying [selectedPositions] of
  /// [plan] to [document], for the live preview of the dialog.
  List<TimelineIssue> remainingIssues(
    LyricDocument document,
    LyricTimelineRepairPlan plan,
    Set<int> selectedPositions, {
    Duration? audioDuration,
  }) {
    final applied = plan.applyTo(document, selectedPositions);
    return validator
        .validate(lines: applied.lines, audioDuration: audioDuration)
        .issues
        .where((issue) => issue.type != TimelineIssueType.extremelyShortGap)
        .toList(growable: false);
  }

  /// How long [text] plausibly takes to sing.
  Duration estimateDuration(String text) {
    final weight = structure.sungWeight(text);
    final estimate = Duration(
      microseconds: (_perSungUnit.inMicroseconds * weight).round(),
    );
    if (estimate < _estimateMin) return _estimateMin;
    if (estimate > _estimateMax) return _estimateMax;
    return _roundToTenMs(estimate);
  }

  /// Which of the rows [above] and [below] (adjacent, out of order) is the
  /// misplaced one, or null when that cannot be told apart.
  ///
  /// A row is the culprit when taking it out leaves its neighbours in order
  /// while taking out the other row would not.
  int? _culprit(List<LyricLine> lines, int above, int below) {
    bool orderedWithout(int removed) {
      final before = removed - 1;
      final after = removed + 1;
      final left = before >= 0 ? lines[before].startTime : null;
      final right = after < lines.length ? lines[after].startTime : null;
      // The pair that remains must be in order.
      final remainingLeft = removed == above
          ? left
          : lines[above].startTime;
      final remainingRight = removed == above
          ? lines[below].startTime
          : right;
      if (remainingLeft != null &&
          remainingRight != null &&
          remainingRight <= remainingLeft) {
        return false;
      }
      return true;
    }

    // A row is plausibly in place when it sits strictly between the rows
    // around it.
    bool fitsBetween(int index) {
      final start = lines[index].startTime;
      if (index > 0 && start <= lines[index - 1].startTime) return false;
      if (index + 1 < lines.length && start >= lines[index + 1].startTime) {
        return false;
      }
      return true;
    }

    final aboveIsCulprit = orderedWithout(above);
    final belowIsCulprit = orderedWithout(below);
    if (aboveIsCulprit && !belowIsCulprit) return above;
    if (belowIsCulprit && !aboveIsCulprit) return below;
    if (aboveIsCulprit && belowIsCulprit) {
      // Both removals restore order; prefer the row that does not fit when
      // judged against its own outer neighbour.
      final aboveOuterOk =
          above == 0 || lines[above].startTime > lines[above - 1].startTime;
      final belowOuterOk =
          below + 1 >= lines.length ||
          lines[below].startTime < lines[below + 1].startTime;
      if (!aboveOuterOk && belowOuterOk) return above;
      if (aboveOuterOk && !belowOuterOk) return below;
      // A duplicated start: the lower row is the one that repeats it.
      if (lines[above].startTime == lines[below].startTime &&
          !fitsBetween(below) &&
          belowOuterOk) {
        return below;
      }
    }
    return null;
  }

  /// A start and end for [index] between its neighbours, or null when the
  /// space is too small.
  (Duration, Duration)? _slotFor(
    List<LyricLine> lines,
    int index,
    Duration? audioDuration,
  ) {
    final line = lines[index];
    final previous = index > 0 ? lines[index - 1] : null;
    final next = index + 1 < lines.length ? lines[index + 1] : null;

    var left = Duration.zero;
    if (previous != null) {
      left = previous.endTime > previous.startTime
          ? previous.endTime
          : previous.startTime + minimumDuration;
    }
    final originalDuration = line.endTime > line.startTime
        ? line.endTime - line.startTime
        : estimateDuration(line.text);
    Duration right;
    if (next != null) {
      right = next.startTime;
      // The row above may itself run past the next start; start just after
      // the row above starts so the order is still restored.
      if (right - left < minimumDuration && previous != null) {
        left = previous.startTime + minimumDuration;
      }
    } else {
      right = left + originalDuration;
      if (audioDuration != null && right > audioDuration) {
        right = audioDuration;
      }
    }
    if (right - left < minimumDuration) return null;
    if (previous != null && left <= previous.startTime) return null;
    if (next != null && left >= next.startTime) return null;

    final available = right - left;
    final duration = originalDuration > available
        ? available
        : originalDuration;
    final end = duration < minimumDuration ? left + minimumDuration : left + duration;
    return (left, end);
  }

  /// An estimated end for a row starting at [start]: never past the next
  /// row's start or the audio end.
  Duration _boundedEnd(
    List<LyricLine> lines,
    int index,
    Duration start,
    Duration? audioDuration,
  ) {
    var end = start + estimateDuration(lines[index].text);
    if (index + 1 < lines.length) {
      final nextStart = lines[index + 1].startTime;
      if (nextStart > start && nextStart < end) end = nextStart;
    }
    if (audioDuration != null && audioDuration > start && end > audioDuration) {
      end = audioDuration;
    }
    return end;
  }

  static Duration _roundToTenMs(Duration value) =>
      Duration(milliseconds: (value.inMilliseconds / 10).round() * 10);
}
