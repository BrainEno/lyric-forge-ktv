import '../../../project/domain/models/lyric_document.dart';
import '../proofreading/forced_alignment_proofread_service.dart';
import 'lyric_manual_edit_marker_service.dart';

/// The recogniser a stretch of the song is run through again.
enum LyricSpanEngine { qwen, whisper }

/// What re-running a stretch should produce.
enum LyricSpanMode {
  /// Recognise the stretch again with Qwen3-ASR; new text and timing.
  recognizeQwen,

  /// Recognise the stretch again with Whisper; new text and timing.
  recognizeWhisper,

  /// Keep the rows' text and let the forced aligner time it again.
  realign;

  LyricSpanEngine? get engine => switch (this) {
    LyricSpanMode.recognizeQwen => LyricSpanEngine.qwen,
    LyricSpanMode.recognizeWhisper => LyricSpanEngine.whisper,
    LyricSpanMode.realign => null,
  };
}

/// How far the stretch reaches past the chosen rows on one side.
///
/// A recogniser cut off mid-word guesses at the fragment, so a little
/// context helps; reaching into a neighbouring row would recognise that row
/// a second time, so no reach ever passes the neighbour's edge.
enum LyricSpanReach {
  none,
  half,
  one,
  two,

  /// Up to the neighbouring row (or the song's edge): recognises a gap
  /// where lyrics are missing, such as an unrecognised chant.
  neighbour;

  /// Null for [neighbour], which has no fixed length.
  Duration? get padding => switch (this) {
    LyricSpanReach.none => Duration.zero,
    LyricSpanReach.half => const Duration(milliseconds: 500),
    LyricSpanReach.one => const Duration(seconds: 1),
    LyricSpanReach.two => const Duration(seconds: 2),
    LyricSpanReach.neighbour => null,
  };
}

/// Rows [first]..[last] (inclusive) and the stretch of the song, on the
/// document's timeline, that is run again.
class LyricSpanWindow {
  final int first;
  final int last;
  final Duration start;
  final Duration end;

  const LyricSpanWindow({
    required this.first,
    required this.last,
    required this.start,
    required this.end,
  });

  Duration get length => end - start;
  int get rowCount => last - first + 1;

  /// The same stretch on the audio's timeline: a document's global offset
  /// shifts every row by the same amount when it is played.
  ({Duration start, Duration end}) onAudio(Duration globalOffset) {
    var start = this.start + globalOffset;
    if (start.isNegative) start = Duration.zero;
    return (start: start, end: end + globalOffset);
  }
}

enum LyricSpanWindowFailure { invalidRange, tooShort, tooLong }

class LyricSpanWindowResult {
  final LyricSpanWindow? window;
  final LyricSpanWindowFailure? failure;

  const LyricSpanWindowResult._(this.window, this.failure);
}

/// Recognised rows for a stretch, on the audio's timeline.
class LyricRecognizedSpan {
  final List<LyricLine> lines;

  /// Model shown to the user, for example `Qwen3-ASR 1.7B`.
  final String engineLabel;
  final String language;

  const LyricRecognizedSpan({
    required this.lines,
    required this.engineLabel,
    required this.language,
  });
}

/// A failure the dialog can show as is.
class LyricSpanRecognitionException implements Exception {
  final String message;

  /// Another recognition, alignment or installation holds the runtime.
  final bool busy;
  final bool cancelled;

  const LyricSpanRecognitionException(
    this.message, {
    this.busy = false,
    this.cancelled = false,
  });

  @override
  String toString() => message;
}

/// Runs one stretch of a project's audio through a recogniser or the forced
/// aligner. Implementations never read or write the lyric document.
///
/// [start] and [end] are on the audio's timeline; so are the results.
abstract interface class LyricSpanRecognizer {
  Future<LyricRecognizedSpan> recognize({
    required String projectId,
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
  });

  Future<List<ForcedAlignedSpan>> align({
    required String projectId,
    required Duration start,
    required Duration end,
    required String text,
    required String language,
  });

  /// Stops the running request; its result, if any, is discarded.
  Future<void> cancel();
}

/// Rows that would replace the chosen ones.
class LyricSpanReplacement {
  final LyricSpanWindow window;
  final List<LyricLine> oldLines;

  /// Clipped to the window, ordered and non-overlapping; no ids yet.
  final List<LyricLine> newLines;

  /// 0–1 similarity of the old and new text, ignoring case, spaces and
  /// punctuation.
  final double similarity;

  /// Chosen rows the user edited by hand.
  final int protectedCount;

  /// Recognised rows dropped because they fell outside the window.
  final int clippedCount;

  const LyricSpanReplacement({
    required this.window,
    required this.oldLines,
    required this.newLines,
    required this.similarity,
    required this.protectedCount,
    required this.clippedCount,
  });

  bool get isEmpty => newLines.isEmpty;

  /// Text-only replacement keeps each row's timing, so it needs one new row
  /// per old row.
  bool get canReplaceTextOnly =>
      newLines.isNotEmpty && newLines.length == oldLines.length;

  bool get changesText {
    if (newLines.length != oldLines.length) return true;
    for (var index = 0; index < newLines.length; index++) {
      if (newLines[index].text.trim() != oldLines[index].text.trim()) {
        return true;
      }
    }
    return false;
  }

  /// Replaces the chosen rows. Rows after them keep their indices shifted
  /// by the change in row count; ids of untouched rows never change.
  ///
  /// With [textOnly] each row keeps its id and timing and takes the new
  /// text; its word timing is kept when the text did not change and
  /// dropped otherwise, because it described the old words.
  LyricDocument applyTo(LyricDocument document, {bool textOnly = false}) {
    if (newLines.isEmpty) return document;
    final lines = document.lines;
    final List<LyricLine> middle;
    if (textOnly && canReplaceTextOnly) {
      middle = [
        for (var index = 0; index < oldLines.length; index++)
          _withText(lines[window.first + index], newLines[index].text),
      ];
    } else {
      middle = newLines;
    }
    final replaced = document.copyWith(
      lines: [
        ...lines.sublist(0, window.first),
        ...middle,
        ...lines.sublist(window.last + 1),
      ],
    );
    return const LyricManualEditMarkerService().assignMissingLineIds(replaced);
  }

  static LyricLine _withText(LyricLine line, String text) {
    if (line.text.trim() == text.trim()) return line;
    return line.copyWith(text: text, words: const []);
  }
}

enum LyricSpanRealignmentStatus {
  ready,

  /// The aligner returned nothing usable.
  noSpans,

  /// A returned word is not the next text of the rows.
  textMismatch,

  /// The aligner stopped before the end of the rows' text.
  incomplete,

  /// None of the chosen rows has sung text to align.
  nothingToAlign,
}

/// New timing for one chosen row.
class LyricSpanRetimedRow {
  final int index;
  final Duration start;
  final Duration end;
  final List<LyricWordTiming> words;

  const LyricSpanRetimedRow({
    required this.index,
    required this.start,
    required this.end,
    required this.words,
  });
}

/// The chosen rows timed again by the forced aligner, text unchanged.
class LyricSpanRealignment {
  final LyricSpanWindow window;
  final LyricSpanRealignmentStatus status;
  final List<LyricSpanRetimedRow> rows;

  /// Row implicated by a failure, if known.
  final int? failedIndex;

  const LyricSpanRealignment({
    required this.window,
    required this.status,
    this.rows = const [],
    this.failedIndex,
  });

  bool get isReady => status == LyricSpanRealignmentStatus.ready;

  /// Rows whose start, end or word timing would change.
  int changedCount(LyricDocument document) => rows.where((row) {
    final line = document.lines[row.index];
    return line.startTime != row.start ||
        line.endTime != row.end ||
        line.words.length != row.words.length;
  }).length;

  LyricDocument applyTo(LyricDocument document) {
    if (!isReady) return document;
    final lines = [...document.lines];
    for (final row in rows) {
      lines[row.index] = lines[row.index].copyWith(
        startTime: row.start,
        endTime: row.end,
        words: row.words,
      );
    }
    return document.copyWith(lines: lines);
  }
}

/// Plans re-running a stretch of rows: which part of the song to send, and
/// how the result replaces or re-times the rows.
///
/// A whole-song recognition sometimes garbles one passage — a loop, a
/// hallucinated line, a chant it skipped — while the rest is fine. Running
/// only that passage again (with the other engine, or with context the
/// first pass lacked) is cheaper than a full re-run and leaves every other
/// row, and every hand edit outside the passage, untouched.
class LyricSpanRerecognitionPlanner {
  const LyricSpanRerecognitionPlanner();

  /// Longer stretches are better served by a full re-run, and Qwen3-ASR
  /// decodes in 30-second chunks.
  static const Duration maxWindow = Duration(seconds: 90);
  static const Duration minWindow = Duration(milliseconds: 500);

  /// Shorter recognised rows (after clipping) are fragments, not rows.
  static const Duration minRowLength = Duration(milliseconds: 120);

  static final RegExp _sung = RegExp(r'[\p{L}\p{N}]', unicode: true);

  LyricSpanWindowResult window(
    LyricDocument document, {
    required int first,
    required int last,
    LyricSpanReach lead = LyricSpanReach.half,
    LyricSpanReach tail = LyricSpanReach.half,
    Duration? audioDuration,
  }) {
    final lines = document.lines;
    if (first < 0 || last >= lines.length || last < first) {
      return const LyricSpanWindowResult._(
        null,
        LyricSpanWindowFailure.invalidRange,
      );
    }
    var rowsStart = lines[first].startTime;
    var rowsEnd = lines[first].endTime;
    for (var index = first; index <= last; index++) {
      final line = lines[index];
      if (line.startTime < rowsStart) rowsStart = line.startTime;
      if (line.endTime > rowsEnd) rowsEnd = line.endTime;
    }
    if (rowsStart.isNegative) rowsStart = Duration.zero;

    // Never reach into a neighbour; when rows already overlap, stay on the
    // chosen rows' own edges.
    final previousEnd = first > 0 ? lines[first - 1].endTime : Duration.zero;
    final floor = previousEnd < rowsStart ? previousEnd : rowsStart;
    final nextStart = last + 1 < lines.length
        ? lines[last + 1].startTime
        : audioDuration;
    Duration? ceiling = nextStart == null
        ? null
        : (nextStart > rowsEnd ? nextStart : rowsEnd);
    if (audioDuration != null && (ceiling == null || ceiling > audioDuration)) {
      ceiling = audioDuration > rowsEnd ? audioDuration : rowsEnd;
    }

    final leadPadding = lead.padding;
    var start = leadPadding == null ? floor : rowsStart - leadPadding;
    if (start < floor) start = floor;
    if (start.isNegative) start = Duration.zero;

    final tailPadding = tail.padding;
    var end = tailPadding == null ? (ceiling ?? rowsEnd) : rowsEnd + tailPadding;
    if (ceiling != null && end > ceiling) end = ceiling;

    final window = LyricSpanWindow(
      first: first,
      last: last,
      start: start,
      end: end,
    );
    if (window.length < minWindow) {
      return LyricSpanWindowResult._(window, LyricSpanWindowFailure.tooShort);
    }
    if (window.length > maxWindow) {
      return LyricSpanWindowResult._(window, LyricSpanWindowFailure.tooLong);
    }
    return LyricSpanWindowResult._(window, null);
  }

  /// [recognized] must already be on the document's timeline.
  LyricSpanReplacement replacement(
    LyricDocument document, {
    required LyricSpanWindow window,
    required List<LyricLine> recognized,
    Set<int> protectedIndices = const {},
  }) {
    final oldLines = document.lines.sublist(window.first, window.last + 1);
    final chorus = oldLines.every((line) => line.isChorus);
    final newLines = <LyricLine>[];
    var clipped = 0;
    final sorted = [...recognized]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    for (final line in sorted) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      var start = line.startTime < window.start ? window.start : line.startTime;
      final end = line.endTime > window.end ? window.end : line.endTime;
      if (newLines.isNotEmpty && start < newLines.last.endTime) {
        start = newLines.last.endTime;
      }
      if (end - start < minRowLength) {
        clipped++;
        continue;
      }
      newLines.add(
        LyricLine(
          text: text,
          startTime: start,
          endTime: end,
          isChorus: chorus,
          confidence: line.confidence,
          confidenceSource: line.confidenceSource,
          words: _clipWords(line.words, start, end),
        ),
      );
    }
    var protectedCount = 0;
    for (var index = window.first; index <= window.last; index++) {
      if (protectedIndices.contains(index)) protectedCount++;
    }
    return LyricSpanReplacement(
      window: window,
      oldLines: List.unmodifiable(oldLines),
      newLines: List.unmodifiable(newLines),
      similarity: similarity(
        oldLines.map((line) => line.text).join(' '),
        newLines.map((line) => line.text).join(' '),
      ),
      protectedCount: protectedCount,
      clippedCount: clipped,
    );
  }

  /// The text the forced aligner is given: the chosen rows with sung text,
  /// one per line.
  String alignmentText(LyricDocument document, LyricSpanWindow window) => [
    for (var index = window.first; index <= window.last; index++)
      if (_normalize(document.lines[index].text).isNotEmpty)
        document.lines[index].text.trim(),
  ].join('\n');

  /// Matches aligned words, already on the document's timeline, to the
  /// chosen rows in order.
  ///
  /// Matching ignores case, spaces and punctuation, because the aligner
  /// returns words without punctuation. A word may run across the end of a
  /// row (the aligner's repair merges words it could not place); it then
  /// times both rows. Anything else that does not match fails the whole
  /// plan: no partial timing is offered.
  LyricSpanRealignment realignment(
    LyricDocument document, {
    required LyricSpanWindow window,
    required List<ForcedAlignedSpan> spans,
  }) {
    final targets = <int, String>{
      for (var index = window.first; index <= window.last; index++)
        if (_normalize(document.lines[index].text).isNotEmpty)
          index: _normalize(document.lines[index].text),
    };
    if (targets.isEmpty) {
      return LyricSpanRealignment(
        window: window,
        status: LyricSpanRealignmentStatus.nothingToAlign,
      );
    }
    final usable = [
      for (final span in spans)
        if (_normalize(span.text).isNotEmpty && span.end > span.start) span,
    ];
    if (usable.isEmpty) {
      return LyricSpanRealignment(
        window: window,
        status: LyricSpanRealignmentStatus.noSpans,
      );
    }

    final order = targets.keys.toList();
    final words = <int, List<LyricWordTiming>>{
      for (final index in order) index: <LyricWordTiming>[],
    };
    var row = 0;
    var position = 0;
    for (final span in usable) {
      var piece = _normalize(span.text);
      final start = _clamp(span.start, window);
      final end = _clamp(span.end, window);
      final whole =
          row < order.length &&
          !_crossesRow(targets[order[row]]!, position, piece);
      while (piece.isNotEmpty) {
        if (row >= order.length) {
          return LyricSpanRealignment(
            window: window,
            status: LyricSpanRealignmentStatus.textMismatch,
            failedIndex: window.last,
          );
        }
        final target = targets[order[row]]!;
        final remaining = target.length - position;
        final take = piece.length < remaining ? piece.length : remaining;
        final chunk = piece.substring(0, take);
        if (target.substring(position, position + take) != chunk) {
          return LyricSpanRealignment(
            window: window,
            status: LyricSpanRealignmentStatus.textMismatch,
            failedIndex: order[row],
          );
        }
        words[order[row]]!.add(
          LyricWordTiming(
            text: whole ? span.text.trim() : chunk,
            start: start,
            end: end,
          ),
        );
        piece = piece.substring(take);
        position += take;
        if (position == target.length) {
          row++;
          position = 0;
        }
      }
    }
    if (row < order.length) {
      return LyricSpanRealignment(
        window: window,
        status: LyricSpanRealignmentStatus.incomplete,
        failedIndex: order[row],
      );
    }

    final rows = <LyricSpanRetimedRow>[];
    for (final index in order) {
      final timed = words[index]!;
      var start = timed.first.start;
      var end = timed.last.end;
      if (end <= start) end = start + const Duration(milliseconds: 1);
      if (rows.isNotEmpty && start < rows.last.end) start = rows.last.end;
      if (end <= start) end = start + const Duration(milliseconds: 1);
      rows.add(
        LyricSpanRetimedRow(
          index: index,
          start: start,
          end: end,
          words: List.unmodifiable(timed),
        ),
      );
    }
    return LyricSpanRealignment(
      window: window,
      status: LyricSpanRealignmentStatus.ready,
      rows: List.unmodifiable(rows),
    );
  }

  /// 0–1 similarity by edit distance on the sung characters.
  static double similarity(String a, String b) {
    final left = _normalize(a).runes.toList();
    final right = _normalize(b).runes.toList();
    if (left.isEmpty && right.isEmpty) return 1;
    if (left.isEmpty || right.isEmpty) return 0;
    const cap = 2000;
    final x = left.length > cap ? left.sublist(0, cap) : left;
    final y = right.length > cap ? right.sublist(0, cap) : right;
    var previous = List<int>.generate(y.length + 1, (index) => index);
    for (var i = 1; i <= x.length; i++) {
      final current = List<int>.filled(y.length + 1, 0)..[0] = i;
      for (var j = 1; j <= y.length; j++) {
        final substitution = previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        var best = substitution < deletion ? substitution : deletion;
        if (insertion < best) best = insertion;
        current[j] = best;
      }
      previous = current;
    }
    final longest = x.length > y.length ? x.length : y.length;
    return 1 - previous[y.length] / longest;
  }

  static bool _crossesRow(String target, int position, String piece) =>
      position + piece.length > target.length;

  static String _normalize(String text) =>
      _sung.allMatches(text.toLowerCase()).map((match) => match[0]).join();

  static Duration _clamp(Duration value, LyricSpanWindow window) {
    if (value < window.start) return window.start;
    if (value > window.end) return window.end;
    return value;
  }

  static List<LyricWordTiming> _clipWords(
    List<LyricWordTiming> words,
    Duration start,
    Duration end,
  ) {
    final clipped = <LyricWordTiming>[];
    for (final word in words) {
      if (word.end < start || word.start > end) continue;
      clipped.add(
        LyricWordTiming(
          text: word.text,
          start: word.start < start ? start : word.start,
          end: word.end > end ? end : word.end,
        ),
      );
    }
    // Word timing that lost words to the clip no longer covers the row's
    // text; dropping it makes export fall back to an even split.
    if (clipped.length != words.length) return const [];
    return List.unmodifiable(clipped);
  }
}
