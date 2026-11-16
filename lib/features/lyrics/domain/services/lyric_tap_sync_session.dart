import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_timeline_repair_planner.dart';

/// How a key press in tap-to-sync (打轴) is read.
enum LyricTapSyncMode {
  /// Each press starts the next row; the previous row ends where the next
  /// one starts unless it was ended explicitly.
  tap,

  /// Pressing starts the row and releasing ends it, so the singer's pauses
  /// are captured as gaps.
  hold,
}

/// One row timed by hand during a tap-to-sync session.
class LyricTapMark {
  final int lineIndex;
  final Duration start;

  /// Explicit end (key released, or "end row" pressed); null means the row
  /// ends where the next marked row starts.
  final Duration? end;

  const LyricTapMark({required this.lineIndex, required this.start, this.end});

  LyricTapMark withEnd(Duration? end) =>
      LyricTapMark(lineIndex: lineIndex, start: start, end: end);

  @override
  String toString() => 'LyricTapMark($lineIndex, $start, $end)';
}

/// The document after a tap-to-sync session, plus what changed.
class LyricTapSyncResult {
  final LyricDocument document;

  /// Rows that got new times from taps, in order.
  final List<int> timedIndices;

  /// Rows after the session that were moved by the session's drift.
  final int shiftedFollowingCount;

  /// The row before the session was cut so it ends where the first tapped
  /// row starts.
  final bool trimmedPrevious;

  const LyricTapSyncResult({
    required this.document,
    required this.timedIndices,
    required this.shiftedFollowingCount,
    required this.trimmedPrevious,
  });

  bool get changed => timedIndices.isNotEmpty;
}

/// The state of one tap-to-sync (打轴) pass over the lyrics.
///
/// The user plays the song and presses a key as each row begins; the session
/// turns those presses into row times. It is pure state, independent of the
/// audio player and the widget that captures the keys, so every rule is
/// testable on its own:
///
/// * presses are taken in lyric order starting at [startIndex]; each press
///   times the row at [cursor] and moves the cursor down;
/// * a press closer than [debounce] to the previous one is a key bounce and
///   is ignored;
/// * a press earlier than the previous row's start means the user went back
///   in the song: rows timed at or after that moment are dropped and the
///   press re-times the first of them ([rewindTo]);
/// * in [LyricTapSyncMode.hold] (or with an explicit "end row") the row gets
///   its own end, so interludes stay empty; otherwise it ends where the next
///   row starts.
class LyricTapSyncSession {
  LyricTapSyncSession({
    required this.lineCount,
    required this.startIndex,
    this.debounce = const Duration(milliseconds: 120),
  }) : assert(startIndex >= 0);

  final int lineCount;
  final int startIndex;

  /// Presses closer together than this are treated as one.
  final Duration debounce;

  /// No row ends less than this after its start.
  static const Duration minimumDuration = Duration(milliseconds: 100);

  /// A row without an explicit end runs to the next row's start, but not
  /// across a pause longer than this: such a gap is an interlude, and the
  /// row then gets a duration estimated from its text instead.
  static const Duration maxCarry = Duration(seconds: 8);

  final List<LyricTapMark> _marks = [];

  List<LyricTapMark> get marks => List.unmodifiable(_marks);

  /// The row the next press times.
  int get cursor => startIndex + _marks.length;

  /// Every row from [startIndex] to the end has been timed.
  bool get isComplete => cursor >= lineCount;

  bool get isEmpty => _marks.isEmpty;

  /// The last timed row while it has no explicit end yet.
  int? get openIndex => _marks.isNotEmpty && _marks.last.end == null
      ? _marks.last.lineIndex
      : null;

  /// Times the row at [cursor] as starting at [time]. Returns whether the
  /// press was taken.
  bool press(Duration time) {
    final at = time.isNegative ? Duration.zero : time;
    if (_marks.isNotEmpty) {
      final last = _marks.last;
      if (at <= last.start) {
        rewindTo(at);
      } else if (at - last.start < debounce) {
        return false;
      }
    }
    if (isComplete) return false;
    if (_marks.isNotEmpty) {
      final last = _marks.last;
      // Pressing for the next row before the previous one was released:
      // the previous row cannot outlast the new one's start.
      if (last.end != null && last.end! > at) {
        _marks[_marks.length - 1] = last.withEnd(at);
      }
    }
    _marks.add(LyricTapMark(lineIndex: cursor, start: at));
    return true;
  }

  /// Ends the open row at [time] (key released in hold mode, or "end row").
  /// Returns whether a row was ended.
  bool release(Duration time) {
    if (openIndex == null) return false;
    final last = _marks.last;
    var end = time;
    if (end < last.start + minimumDuration) {
      end = last.start + minimumDuration;
    }
    _marks[_marks.length - 1] = last.withEnd(end);
    return true;
  }

  /// Takes back the last action: an explicit end first, then the last
  /// press. Returns the start of the row that is to be timed again (so the
  /// caller can seek back before it), or null when there was nothing to
  /// undo.
  Duration? undo() {
    if (_marks.isEmpty) return null;
    final last = _marks.last;
    if (last.end != null) {
      _marks[_marks.length - 1] = last.withEnd(null);
      return last.start;
    }
    _marks.removeLast();
    return last.start;
  }

  /// Forgets rows timed at or after [time] and re-opens a row whose end is
  /// after it. Returns how many timed rows were dropped.
  int rewindTo(Duration time) {
    var dropped = 0;
    while (_marks.isNotEmpty && _marks.last.start >= time) {
      _marks.removeLast();
      dropped++;
    }
    if (_marks.isNotEmpty) {
      final last = _marks.last;
      if (last.end != null && last.end! > time) {
        _marks[_marks.length - 1] = last.withEnd(null);
      }
    }
    return dropped;
  }

  /// [document] with the session's times applied as one change.
  ///
  /// * Timed rows get their tapped start; the end is the explicit end, else
  ///   the next timed row's start — unless that is more than [maxCarry]
  ///   away, in which case the duration is estimated from the text.
  /// * The last timed row without an explicit end runs to the next
  ///   (untimed) row's start when that is close, otherwise it keeps its old
  ///   duration or an estimate.
  /// * With [shiftFollowing], the rows after the session move by the drift
  ///   measured at the last timed row, which is what usually happened to
  ///   them too (a different audio master, a wrong global offset).
  /// * The row before the session is cut if it would overlap the first
  ///   timed row.
  /// * Timed rows are recorded as [LyricTimingProvenance.manual], which the
  ///   proofreading flows treat as protected timing.
  LyricTapSyncResult apply(
    LyricDocument document, {
    bool shiftFollowing = false,
    LyricTimelineRepairPlanner estimator = const LyricTimelineRepairPlanner(),
  }) {
    final usable = _marks
        .where((mark) => mark.lineIndex < document.lines.length)
        .toList(growable: false);
    if (usable.isEmpty) {
      return LyricTapSyncResult(
        document: document,
        timedIndices: const [],
        shiftedFollowingCount: 0,
        trimmedPrevious: false,
      );
    }
    final lines = List<LyricLine>.from(document.lines);
    final provenance = <String, Object?>{
      ...?_stringMap(document.metadata[kLyricTimingProvenanceKey]),
    };

    final lastMark = usable.last;
    final drift = lastMark.start - document.lines[lastMark.lineIndex].startTime;
    var shifted = 0;
    if (shiftFollowing && drift != Duration.zero) {
      for (var index = lastMark.lineIndex + 1; index < lines.length; index++) {
        final line = lines[index];
        lines[index] = line.copyWith(
          startTime: _nonNegative(line.startTime + drift),
          endTime: _nonNegative(line.endTime + drift),
        );
        shifted++;
      }
    }

    for (var position = 0; position < usable.length; position++) {
      final mark = usable[position];
      final original = lines[mark.lineIndex];
      final nextStart = position + 1 < usable.length
          ? usable[position + 1].start
          : (mark.lineIndex + 1 < lines.length
                ? lines[mark.lineIndex + 1].startTime
                : null);
      final end =
          mark.end ?? _implicitEnd(mark, original, nextStart, estimator);
      lines[mark.lineIndex] = original.copyWith(
        startTime: mark.start,
        endTime: end,
      );
      final id = original.id;
      if (id != null) provenance[id] = LyricTimingProvenance.manual.name;
    }

    var trimmedPrevious = false;
    final first = usable.first;
    if (first.lineIndex > 0) {
      final previous = lines[first.lineIndex - 1];
      if (previous.endTime > first.start &&
          first.start - previous.startTime >= minimumDuration) {
        lines[first.lineIndex - 1] = previous.copyWith(endTime: first.start);
        trimmedPrevious = true;
      }
    }

    return LyricTapSyncResult(
      document: document.copyWith(
        lines: lines,
        metadata: {...document.metadata, kLyricTimingProvenanceKey: provenance},
      ),
      timedIndices: [for (final mark in usable) mark.lineIndex],
      shiftedFollowingCount: shifted,
      trimmedPrevious: trimmedPrevious,
    );
  }

  Duration _implicitEnd(
    LyricTapMark mark,
    LyricLine original,
    Duration? nextStart,
    LyricTimelineRepairPlanner estimator,
  ) {
    if (nextStart != null &&
        nextStart > mark.start &&
        nextStart - mark.start <= maxCarry) {
      return nextStart - mark.start < minimumDuration
          ? mark.start + minimumDuration
          : nextStart;
    }
    final oldDuration = original.endTime - original.startTime;
    final duration = oldDuration > Duration.zero && oldDuration <= maxCarry
        ? oldDuration
        : estimator.estimateDuration(original.text);
    var end = mark.start + duration;
    if (nextStart != null && nextStart > mark.start && end > nextStart) {
      end = nextStart;
    }
    if (end < mark.start + minimumDuration) end = mark.start + minimumDuration;
    return end;
  }

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;

  static Map<String, Object?>? _stringMap(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
