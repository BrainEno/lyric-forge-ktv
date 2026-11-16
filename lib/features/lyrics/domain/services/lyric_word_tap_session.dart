import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
import 'lyric_karaoke_timing_service.dart';
import 'lyric_tap_sync_session.dart';

/// One row in a word-by-word tap-to-sync pass: its index and the units the
/// user presses for (a Han character, kana, Hangul syllable or Latin word,
/// with its punctuation, as karaoke export highlights them).
class LyricWordTapRow {
  final int lineIndex;
  final List<String> units;

  const LyricWordTapRow({required this.lineIndex, required this.units});
}

/// One unit timed by hand.
class LyricWordTapMark {
  /// Position of the row in [LyricWordTapSession.rows].
  final int rowPosition;
  final int unitIndex;
  final Duration start;

  /// Explicit end (key released, or "end word" pressed); null means the
  /// unit lasts until the next press.
  final Duration? end;

  const LyricWordTapMark({
    required this.rowPosition,
    required this.unitIndex,
    required this.start,
    this.end,
  });

  LyricWordTapMark withEnd(Duration? end) => LyricWordTapMark(
    rowPosition: rowPosition,
    unitIndex: unitIndex,
    start: start,
    end: end,
  );

  @override
  String toString() =>
      'LyricWordTapMark($rowPosition:$unitIndex, $start, $end)';
}

/// The document after a word-by-word session, plus what changed.
class LyricWordTapResult {
  final LyricDocument document;

  /// Rows whose every unit was timed; they got word timing and new row
  /// times.
  final List<int> timedIndices;

  /// A row the session stopped in the middle of; it is left unchanged.
  final int? partialIndex;

  /// The row before the session was cut so it ends where the first timed
  /// row starts.
  final bool trimmedPrevious;

  const LyricWordTapResult({
    required this.document,
    required this.timedIndices,
    required this.partialIndex,
    required this.trimmedPrevious,
  });

  bool get changed => timedIndices.isNotEmpty;
}

/// The state of one word-by-word tap-to-sync (逐字打轴) pass.
///
/// Like [LyricTapSyncSession], but the user presses once per sung unit
/// instead of once per row, which is how karaoke lyrics are timed by hand.
/// The result is real word timing ([LyricLine.words]) that karaoke export,
/// splitting and the inspector use.
///
/// * Units are taken in lyric order from [startIndex]; rows without any sung
///   unit (empty rows, `♪`) are skipped.
/// * A press closer than [debounce] to the previous one is a key bounce.
///   Syllables follow each other fast, so the default is shorter than for
///   rows.
/// * A press earlier than the previous unit's start means the user went
///   back: units timed at or after that moment are dropped ([rewindTo]).
/// * A unit ends at its explicit end (hold mode, or "end word"), otherwise
///   at the next press. The last unit of a row without an explicit end runs
///   into the next row's first press only when that is at most
///   [maxTailCarry] later — a longer gap is a breath or an interlude — and
///   otherwise gets the row's average unit length.
class LyricWordTapSession {
  LyricWordTapSession({
    required List<LyricLine> lines,
    required this.startIndex,
    this.debounce = const Duration(milliseconds: 60),
    LyricKaraokeTimingService karaoke = const LyricKaraokeTimingService(),
  }) : rows = List.unmodifiable(_rowsFrom(lines, startIndex, karaoke));

  final int startIndex;
  final Duration debounce;

  /// The rows to time, in order.
  final List<LyricWordTapRow> rows;

  /// No unit ends less than this after its start.
  static const Duration minimumUnit = Duration(milliseconds: 60);

  /// The last unit of a row runs into the next row's first press only
  /// across a gap up to this long.
  static const Duration maxTailCarry = Duration(milliseconds: 1500);

  /// Bounds of the estimated length of a row's last unit.
  static const Duration minimumTail = Duration(milliseconds: 200);
  static const Duration maximumTail = Duration(milliseconds: 1500);

  /// A unit never lasts longer than this without an explicit end; a longer
  /// wait before the next press is a pause, not one held syllable.
  static const Duration maxCarry = LyricTapSyncSession.maxCarry;

  final List<LyricWordTapMark> _marks = [];

  /// Flat index of the first unit of every row, plus the total at the end.
  late final List<int> _rowOffsets = () {
    final offsets = <int>[0];
    for (final row in rows) {
      offsets.add(offsets.last + row.units.length);
    }
    return offsets;
  }();

  List<LyricWordTapMark> get marks => List.unmodifiable(_marks);

  int get unitCount => _rowOffsets.last;

  bool get isEmpty => _marks.isEmpty;

  bool get isComplete => _marks.length >= unitCount;

  /// Position in [rows] of the unit the next press times (or of the last
  /// row once complete).
  int get cursorRow {
    if (rows.isEmpty) return 0;
    if (isComplete) return rows.length - 1;
    return _rowAt(_marks.length);
  }

  /// Index in its row of the unit the next press times; null once
  /// complete.
  int? get cursorUnit {
    if (isComplete) return null;
    return _marks.length - _rowOffsets[cursorRow];
  }

  /// How many units of [rowPosition] have been timed.
  int timedUnitsIn(int rowPosition) {
    final from = _rowOffsets[rowPosition];
    final count = _marks.length - from;
    if (count <= 0) return 0;
    final total = rows[rowPosition].units.length;
    return count > total ? total : count;
  }

  /// Rows whose every unit has been timed.
  int get completedRowCount {
    var count = 0;
    for (var position = 0; position < rows.length; position++) {
      if (timedUnitsIn(position) == rows[position].units.length) count++;
    }
    return count;
  }

  /// The last timed unit while it has no explicit end.
  bool get hasOpenUnit => _marks.isNotEmpty && _marks.last.end == null;

  int _rowAt(int flatIndex) {
    var low = 0;
    var high = rows.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_rowOffsets[middle] <= flatIndex) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// Times the unit at the cursor as starting at [time]. Returns whether
  /// the press was taken.
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
      if (last.end != null && last.end! > at) {
        _marks[_marks.length - 1] = last.withEnd(at);
      }
    }
    final flat = _marks.length;
    final row = _rowAt(flat);
    _marks.add(
      LyricWordTapMark(
        rowPosition: row,
        unitIndex: flat - _rowOffsets[row],
        start: at,
      ),
    );
    return true;
  }

  /// Ends the open unit at [time]. Returns whether a unit was ended.
  bool release(Duration time) {
    if (!hasOpenUnit) return false;
    final last = _marks.last;
    var end = time;
    if (end < last.start + minimumUnit) end = last.start + minimumUnit;
    _marks[_marks.length - 1] = last.withEnd(end);
    return true;
  }

  /// Takes back the last action: an explicit end first, then the last
  /// press. Returns the start of the unit to be timed again, or null.
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

  /// Forgets units timed at or after [time]. Returns how many were dropped.
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

  /// Where the session should resume after going back to the row of the
  /// last timed unit: that row's first press, or null.
  Duration? rowStart(int rowPosition) {
    final from = _rowOffsets[rowPosition];
    return from < _marks.length ? _marks[from].start : null;
  }

  /// [document] with the fully timed rows applied as one change.
  ///
  /// Every fully timed row gets [LyricLine.words] (one entry per unit, text
  /// with its punctuation), starts at its first press and ends where its
  /// last unit ends. A row the session stopped inside is left alone. The
  /// row before the session is cut if it would overlap, and a timed row's
  /// end is pulled in before an untimed next row it would otherwise run
  /// into. Timed rows are recorded as [LyricTimingProvenance.manual].
  LyricWordTapResult apply(LyricDocument document) {
    final lines = List<LyricLine>.from(document.lines);
    final provenance = <String, Object?>{
      ...?_stringMap(document.metadata[kLyricTimingProvenanceKey]),
    };
    final timed = <int>[];
    int? partial;

    for (var position = 0; position < rows.length; position++) {
      final row = rows[position];
      final count = timedUnitsIn(position);
      if (count == 0) break;
      if (row.lineIndex >= lines.length) break;
      if (count < row.units.length) {
        partial = row.lineIndex;
        break;
      }
      final from = _rowOffsets[position];
      final rowMarks = _marks.sublist(from, from + row.units.length);
      final nextPress = from + row.units.length < _marks.length
          ? _marks[from + row.units.length].start
          : null;
      final untimedNext = nextPress == null && row.lineIndex + 1 < lines.length
          ? lines[row.lineIndex + 1].startTime
          : null;
      final words = <LyricWordTiming>[];
      for (var unit = 0; unit < rowMarks.length; unit++) {
        final mark = rowMarks[unit];
        final Duration end;
        if (mark.end != null) {
          end = mark.end!;
        } else if (unit + 1 < rowMarks.length) {
          end = _cap(mark.start, rowMarks[unit + 1].start, rowMarks);
        } else {
          end = _tailEnd(mark.start, rowMarks, nextPress, untimedNext);
        }
        words.add(
          LyricWordTiming(text: row.units[unit], start: mark.start, end: end),
        );
      }
      final original = lines[row.lineIndex];
      lines[row.lineIndex] = original.copyWith(
        startTime: words.first.start,
        endTime: words.last.end,
        words: List.unmodifiable(words),
      );
      final id = original.id;
      if (id != null) provenance[id] = LyricTimingProvenance.manual.name;
      timed.add(row.lineIndex);
    }

    var trimmedPrevious = false;
    if (timed.isNotEmpty && timed.first > 0) {
      final first = lines[timed.first];
      final previous = lines[timed.first - 1];
      if (previous.endTime > first.startTime &&
          first.startTime - previous.startTime >=
              LyricTapSyncSession.minimumDuration) {
        lines[timed.first - 1] = previous.copyWith(endTime: first.startTime);
        trimmedPrevious = true;
      }
    }

    if (timed.isEmpty) {
      return LyricWordTapResult(
        document: document,
        timedIndices: const [],
        partialIndex: partial,
        trimmedPrevious: false,
      );
    }
    return LyricWordTapResult(
      document: document.copyWith(
        lines: lines,
        metadata: {...document.metadata, kLyricTimingProvenanceKey: provenance},
      ),
      timedIndices: List.unmodifiable(timed),
      partialIndex: partial,
      trimmedPrevious: trimmedPrevious,
    );
  }

  /// A unit without an explicit end runs to [next], but not across a pause
  /// longer than [maxCarry].
  Duration _cap(
    Duration start,
    Duration next,
    List<LyricWordTapMark> rowMarks,
  ) {
    if (next - start <= maxCarry) return next;
    final end = start + _averageUnit(rowMarks);
    return end > next ? next : end;
  }

  Duration _tailEnd(
    Duration start,
    List<LyricWordTapMark> rowMarks,
    Duration? nextPress,
    Duration? untimedNext,
  ) {
    if (nextPress != null && nextPress - start <= maxTailCarry) {
      return nextPress - start < minimumUnit ? start + minimumUnit : nextPress;
    }
    var end = start + _averageUnit(rowMarks);
    if (nextPress != null && end > nextPress) end = nextPress;
    if (untimedNext != null &&
        untimedNext - start >= minimumUnit &&
        end > untimedNext) {
      end = untimedNext;
    }
    if (end < start + minimumUnit) end = start + minimumUnit;
    return end;
  }

  /// The row's average unit length from its presses, within
  /// [minimumTail]–[maximumTail]. A one-unit row gets the upper bound: a
  /// single word on its own is usually held.
  Duration _averageUnit(List<LyricWordTapMark> rowMarks) {
    if (rowMarks.length < 2) return maximumTail;
    final span = rowMarks.last.start - rowMarks.first.start;
    final average = Duration(
      microseconds: span.inMicroseconds ~/ (rowMarks.length - 1),
    );
    if (average < minimumTail) return minimumTail;
    if (average > maximumTail) return maximumTail;
    return average;
  }

  static List<LyricWordTapRow> _rowsFrom(
    List<LyricLine> lines,
    int startIndex,
    LyricKaraokeTimingService karaoke,
  ) {
    final rows = <LyricWordTapRow>[];
    for (
      var index = startIndex < 0 ? 0 : startIndex;
      index < lines.length;
      index++
    ) {
      final units = karaoke.units(lines[index].text);
      if (units.isEmpty || units.every((unit) => unit.weight <= 0)) continue;
      rows.add(
        LyricWordTapRow(
          lineIndex: index,
          units: List.unmodifiable([for (final unit in units) unit.text]),
        ),
      );
    }
    return rows;
  }

  static Map<String, Object?>? _stringMap(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
