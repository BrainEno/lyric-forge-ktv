import '../../../project/domain/models/lyric_document.dart';
import 'lyric_word_timing_service.dart';

/// What the word timing check found in a row.
enum LyricWordTimingIssueKind {
  /// The row's words no longer match its text (characters were added or
  /// removed), so export ignores them. Fix: clear them.
  stale,

  /// The words lie outside the row because the row was moved or stretched
  /// since; they are mapped onto the row on the fly. Fix: store the mapped
  /// times, so other tools and older versions see what export uses.
  drifted,

  /// A word is held implausibly long: a long note, or an alignment that
  /// swallowed a pause. Listen; nothing is changed.
  longWord,

  /// Characters squeezed into almost no time, which aligners produce when
  /// they lose track. Listen and fine-tune; nothing is changed.
  shortWords,

  /// A long silence between two words inside the row, usually a breath or
  /// an interlude the row should be split at. Nothing is changed.
  innerGap,
}

/// One finding of the word timing check.
class LyricWordTimingIssue {
  final LyricWordTimingIssueKind kind;

  /// Row index in the document.
  final int index;

  /// The row as it is now.
  final LyricLine line;

  /// The row after the fix, or null when the finding is only listed.
  final LyricLine? proposed;

  /// The word concerned ([LyricWordTimingIssueKind.longWord],
  /// [LyricWordTimingIssueKind.innerGap]: the word after the gap).
  final String? word;

  /// The long word's length, or the gap's length.
  final Duration? duration;

  /// How many characters are too short ([LyricWordTimingIssueKind.shortWords]).
  final int count;

  /// The recorded span of the words ([LyricWordTimingIssueKind.drifted]).
  final Duration? recordedStart;
  final Duration? recordedEnd;

  const LyricWordTimingIssue({
    required this.kind,
    required this.index,
    required this.line,
    this.proposed,
    this.word,
    this.duration,
    this.count = 0,
    this.recordedStart,
    this.recordedEnd,
  });

  bool get fixable => proposed != null;
}

/// The result of a word timing check over a whole document.
class LyricWordTimingPlan {
  final List<LyricWordTimingIssue> issues;

  /// Rows with usable word timing.
  final int timedRows;

  /// Rows with sung text.
  final int sungRows;

  const LyricWordTimingPlan({
    required this.issues,
    required this.timedRows,
    required this.sungRows,
  });

  /// Positions in [issues] that can be fixed; all are selected by default,
  /// since neither fix changes what export produces.
  List<int> get fixablePositions => [
    for (var position = 0; position < issues.length; position++)
      if (issues[position].fixable) position,
  ];

  int countOf(LyricWordTimingIssueKind kind) =>
      issues.where((issue) => issue.kind == kind).length;

  /// [document] with the fixes at [positions] applied. Only word timing
  /// changes; text and row times stay as they are.
  LyricDocument applyTo(LyricDocument document, Set<int> positions) {
    final replacements = <int, LyricLine>{};
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      final proposed = issue.proposed;
      if (proposed == null || issue.index >= document.lines.length) continue;
      replacements[issue.index] = proposed;
    }
    if (replacements.isEmpty) return document;
    return document.copyWith(
      lines: [
        for (var index = 0; index < document.lines.length; index++)
          replacements[index] ?? document.lines[index],
      ],
    );
  }
}

/// Checks the word timing ([LyricLine.words]) of every row: whether it still
/// matches the text, whether it has drifted from the row, and whether any
/// word is held too long, squeezed too short or separated by a long silence.
///
/// Recognition, karaoke imports, word tap-to-sync and fine-tuning all write
/// word timing; this is the one place that shows where it is missing,
/// invalid or worth a listen before exporting karaoke formats.
class LyricWordTimingAuditor {
  const LyricWordTimingAuditor({
    this.wordTiming = const LyricWordTimingService(),
    this.longWord = const Duration(milliseconds: 2500),
    this.shortCharacter = const Duration(milliseconds: 40),
    this.innerGap = const Duration(milliseconds: 1200),
  });

  final LyricWordTimingService wordTiming;

  /// A word held at least this long is listed.
  final Duration longWord;

  /// A sung character shorter than this is squeezed.
  final Duration shortCharacter;

  /// A silence between words at least this long is listed.
  final Duration innerGap;

  LyricWordTimingPlan plan(LyricDocument document) {
    final issues = <LyricWordTimingIssue>[];
    var timed = 0;
    var sung = 0;
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      if (wordTiming.sungCount(line.text) > 0) sung++;
      if (line.words.isEmpty) continue;
      if (!wordTiming.isUsable(line)) {
        issues.add(
          LyricWordTimingIssue(
            kind: LyricWordTimingIssueKind.stale,
            index: index,
            line: line,
            proposed: line.copyWith(words: const []),
          ),
        );
        continue;
      }
      timed++;
      issues.addAll(_check(index, line));
    }
    return LyricWordTimingPlan(
      issues: List.unmodifiable(issues),
      timedRows: timed,
      sungRows: sung,
    );
  }

  List<LyricWordTimingIssue> _check(int index, LyricLine line) {
    final issues = <LyricWordTimingIssue>[];
    var recordedStart = line.words.first.start;
    var recordedEnd = line.words.first.end;
    for (final word in line.words) {
      if (word.start < recordedStart) recordedStart = word.start;
      if (word.end > recordedEnd) recordedEnd = word.end;
    }
    final tolerance = wordTiming.tolerance;
    if (recordedStart < line.startTime - tolerance ||
        recordedEnd > line.endTime + tolerance) {
      issues.add(
        LyricWordTimingIssue(
          kind: LyricWordTimingIssueKind.drifted,
          index: index,
          line: line,
          proposed: line.copyWith(words: wordTiming.normalized(line)),
          recordedStart: recordedStart,
          recordedEnd: recordedEnd,
        ),
      );
    }

    final words = wordTiming.normalized(line);
    LyricWordTiming? longest;
    for (final word in words) {
      final length = word.end - word.start;
      if (length >= longWord &&
          (longest == null || length > longest.end - longest.start)) {
        longest = word;
      }
    }
    if (longest != null) {
      issues.add(
        LyricWordTimingIssue(
          kind: LyricWordTimingIssueKind.longWord,
          index: index,
          line: line,
          word: longest.text,
          duration: longest.end - longest.start,
        ),
      );
    }

    final times = wordTiming.characterTimes(line) ?? const [];
    final squeezed = times
        .where((time) => time.end - time.start < shortCharacter)
        .length;
    if (squeezed > 0) {
      issues.add(
        LyricWordTimingIssue(
          kind: LyricWordTimingIssueKind.shortWords,
          index: index,
          line: line,
          count: squeezed,
        ),
      );
    }

    Duration? widest;
    String? after;
    for (var position = 1; position < words.length; position++) {
      final gap = words[position].start - words[position - 1].end;
      if (gap >= innerGap && (widest == null || gap > widest)) {
        widest = gap;
        after = words[position].text;
      }
    }
    if (widest != null) {
      issues.add(
        LyricWordTimingIssue(
          kind: LyricWordTimingIssueKind.innerGap,
          index: index,
          line: line,
          word: after,
          duration: widest,
        ),
      );
    }
    return issues;
  }
}
