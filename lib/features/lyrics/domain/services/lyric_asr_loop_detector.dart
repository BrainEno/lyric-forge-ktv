import '../../../project/domain/models/lyric_document.dart';
import 'lyric_line_structure_service.dart';
import 'lyric_word_timing_service.dart';

/// What kind of recognition loop a finding is.
enum LyricAsrLoopKind {
  /// One row repeats a short unit far more often than a lyric would
  /// (`我爱你我爱你我爱你我爱你我爱你…`, `啊啊啊啊啊啊啊啊啊啊`): the decoder got stuck.
  inRowRepeat,

  /// Several consecutive rows have the same text: the recogniser kept
  /// emitting the last phrase over an interlude or a long note.
  repeatedRows,
}

/// One repeated run inside a row.
class LyricAsrLoopRun {
  /// The repeated unit as it first appears, for display.
  final String unit;

  /// How many times the unit occurs back to back.
  final int repeats;

  /// How many repeats the proposed text keeps.
  final int kept;

  /// The unit is one character of a spaceless script (啊, 啦), which songs
  /// hold and repeat more than words.
  final bool singleCharacter;

  /// UTF-16 range of the whole run in the row text.
  final int start;
  final int end;

  /// UTF-16 offset where the kept repeats end.
  final int keptEnd;

  const LyricAsrLoopRun({
    required this.unit,
    required this.repeats,
    required this.kept,
    this.singleCharacter = false,
    required this.start,
    required this.end,
    required this.keptEnd,
  });
}

/// One finding of [LyricAsrLoopDetector].
class LyricAsrLoopIssue {
  final LyricAsrLoopKind kind;

  /// The (first) row the finding is about.
  final int index;

  /// [LyricAsrLoopKind.inRowRepeat]: the loops in the row.
  final List<LyricAsrLoopRun> runs;

  /// [LyricAsrLoopKind.inRowRepeat]: the row text with every loop cut down
  /// to a few repeats.
  final String? proposedText;

  /// [LyricAsrLoopKind.repeatedRows]: every row of the run, in order.
  final List<int> runIndices;

  /// [LyricAsrLoopKind.repeatedRows]: the rows the fix deletes (the run
  /// minus the rows kept, minus hand-edited rows).
  final List<int> removedIndices;

  /// The repeat count is far beyond what songs do, so the fix is selected
  /// by default. Weaker findings are listed for listening, unselected.
  final bool strong;

  /// The fix would change a hand-edited row, so it is only listed.
  final bool protected;

  const LyricAsrLoopIssue._({
    required this.kind,
    required this.index,
    this.runs = const [],
    this.proposedText,
    this.runIndices = const [],
    this.removedIndices = const [],
    required this.strong,
    required this.protected,
  });

  /// Whether applying the finding changes anything.
  bool get fixable =>
      !protected &&
      switch (kind) {
        LyricAsrLoopKind.inRowRepeat => proposedText != null,
        LyricAsrLoopKind.repeatedRows => removedIndices.isNotEmpty,
      };

  /// The highest repeat count of the finding.
  int get repeats => switch (kind) {
    LyricAsrLoopKind.inRowRepeat => runs.fold(
      0,
      (best, run) => run.repeats > best ? run.repeats : best,
    ),
    LyricAsrLoopKind.repeatedRows => runIndices.length,
  };
}

/// The findings for a document and how to apply a selection of them.
class LyricAsrLoopPlan {
  final List<LyricAsrLoopIssue> issues;

  const LyricAsrLoopPlan(this.issues);

  static const LyricAsrLoopPlan empty = LyricAsrLoopPlan([]);

  /// Positions in [issues] that can be applied.
  List<int> get fixablePositions => [
    for (var i = 0; i < issues.length; i++)
      if (issues[i].fixable) i,
  ];

  /// Positions selected by default: strong, fixable findings.
  List<int> get defaultPositions => [
    for (var i = 0; i < issues.length; i++)
      if (issues[i].fixable && issues[i].strong) i,
  ];

  /// How many rows a selection rewrites and deletes.
  ({int rewritten, int removed}) countFor(Set<int> positions) {
    final removed = <int>{};
    final rewritten = <int>{};
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      if (!issue.fixable) continue;
      if (issue.kind == LyricAsrLoopKind.repeatedRows) {
        removed.addAll(issue.removedIndices);
      } else {
        rewritten.add(issue.index);
      }
    }
    rewritten.removeAll(removed);
    return (rewritten: rewritten.length, removed: removed.length);
  }

  /// [document] with the selected findings applied: looping rows rewritten,
  /// repeated rows deleted. Rows keep their ids and timing. A rewritten row
  /// with usable word timing keeps the timing of the words that remain.
  LyricDocument applyTo(
    LyricDocument document,
    Set<int> positions, {
    LyricWordTimingService wordTiming = const LyricWordTimingService(),
  }) {
    final texts = <int, String>{};
    final runs = <int, List<LyricAsrLoopRun>>{};
    final removed = <int>{};
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      if (!issue.fixable) continue;
      if (issue.kind == LyricAsrLoopKind.repeatedRows) {
        removed.addAll(issue.removedIndices);
      } else {
        texts[issue.index] = issue.proposedText!;
        runs[issue.index] = issue.runs;
      }
    }
    if (texts.isEmpty && removed.isEmpty) return document;
    final lines = <LyricLine>[];
    for (var index = 0; index < document.lines.length; index++) {
      if (removed.contains(index)) continue;
      final line = document.lines[index];
      final text = texts[index];
      if (text == null) {
        lines.add(line);
        continue;
      }
      final words = keptWords(line, runs[index]!, wordTiming);
      lines.add(
        words == null
            ? line.copyWith(text: text)
            : line.copyWith(text: text, words: words),
      );
    }
    return document.copyWith(lines: lines);
  }

  /// The word timing of the parts of [line] that [runs] keep, or null when
  /// the row has no usable word timing.
  static List<LyricWordTiming>? keptWords(
    LyricLine line,
    List<LyricAsrLoopRun> runs,
    LyricWordTimingService wordTiming,
  ) {
    if (!wordTiming.isUsable(line)) return null;
    final text = line.text;
    int sungBefore(int offset) =>
        wordTiming.sungCount(text.substring(0, offset));
    final words = <LyricWordTiming>[];
    var cursor = 0;
    for (final run in runs) {
      words.addAll(wordTiming.slice(line, cursor, sungBefore(run.keptEnd)));
      cursor = sungBefore(run.end);
    }
    words.addAll(wordTiming.slice(line, cursor, wordTiming.sungCount(text)));
    return List.unmodifiable(words);
  }
}

/// Finds recognition loops: rows where the decoder repeated itself.
///
/// Speech recognisers trained on subtitles loop when the audio stops
/// matching what they expect — over long notes, interludes and heavy
/// accompaniment. The result is one row with a phrase repeated a dozen
/// times, or a run of identical rows; both are impossible to sing along to
/// and easy to miss while scrolling. Songs repeat too, so the thresholds
/// sit above ordinary lyric repetition and only clear loops are selected by
/// default:
///
/// * **In a row**: a unit of 1–[maxUnitTokens] sung tokens (a Han
///   character, kana or Hangul syllable, or a Latin word) occurring back to
///   back at least [minUnitRepeats] times ([minSingleRepeats] for a single
///   character, since `啦啦啦啦` is a lyric). Strong from [strongUnitRepeats]
///   ([strongSingleRepeats]). The fix keeps [keepUnitRepeats]
///   ([keepSingleRepeats]) and drops the rest of the run, leaving the text
///   around it alone.
/// * **Across rows**: at least [minRowRepeats] consecutive rows with the same
///   sung text (punctuation, spacing and letter case ignored). Strong from
///   [strongRowRepeats]. The fix keeps the first [keepRowRepeats] rows.
///
/// Hand-edited rows ([plan]'s `protectedIndices`) are never rewritten or
/// deleted; a finding that would only touch them is listed without a fix.
class LyricAsrLoopDetector {
  const LyricAsrLoopDetector({
    this.structure = const LyricLineStructureService(),
    this.maxUnitTokens = 8,
    this.minUnitRepeats = 4,
    this.strongUnitRepeats = 6,
    this.keepUnitRepeats = 2,
    this.minSingleRepeats = 8,
    this.strongSingleRepeats = 12,
    this.keepSingleRepeats = 4,
    this.minRowRepeats = 4,
    this.strongRowRepeats = 6,
    this.keepRowRepeats = 2,
  });

  final LyricLineStructureService structure;
  final int maxUnitTokens;
  final int minUnitRepeats;
  final int strongUnitRepeats;
  final int keepUnitRepeats;
  final int minSingleRepeats;
  final int strongSingleRepeats;
  final int keepSingleRepeats;
  final int minRowRepeats;
  final int strongRowRepeats;
  final int keepRowRepeats;

  /// Every finding in [document], in row order.
  LyricAsrLoopPlan plan(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
  }) {
    final issues = <LyricAsrLoopIssue>[];
    final lines = document.lines;
    final keys = [for (final line in lines) rowKey(line.text)];

    final inRow = <int, LyricAsrLoopIssue>{};
    for (var index = 0; index < lines.length; index++) {
      final runs = loops(lines[index].text);
      if (runs.isEmpty) continue;
      final proposed = collapse(lines[index].text, runs);
      inRow[index] = LyricAsrLoopIssue._(
        kind: LyricAsrLoopKind.inRowRepeat,
        index: index,
        runs: runs,
        proposedText: proposed == lines[index].text ? null : proposed,
        strong: runs.any(_isStrong),
        protected: protectedIndices.contains(index),
      );
    }

    var index = 0;
    while (index < lines.length) {
      final key = keys[index];
      var end = index + 1;
      if (key.isNotEmpty) {
        while (end < lines.length && keys[end] == key) {
          end++;
        }
      }
      final length = end - index;
      // Rows of a run come before the in-row findings they contain, so the
      // list reads top to bottom.
      for (var row = index; row < end; row++) {
        final finding = inRow[row];
        if (finding != null && length < minRowRepeats) issues.add(finding);
      }
      if (key.isNotEmpty && length >= minRowRepeats) {
        final run = [for (var row = index; row < end; row++) row];
        final removed = [
          for (final row in run.skip(keepRowRepeats))
            if (!protectedIndices.contains(row)) row,
        ];
        issues.add(
          LyricAsrLoopIssue._(
            kind: LyricAsrLoopKind.repeatedRows,
            index: index,
            runIndices: List.unmodifiable(run),
            removedIndices: List.unmodifiable(removed),
            strong: length >= strongRowRepeats,
            protected: removed.isEmpty,
          ),
        );
        // A row kept by the run can still loop inside; deleted rows need no
        // second fix.
        for (final row in run.take(keepRowRepeats)) {
          final finding = inRow[row];
          if (finding != null) issues.add(finding);
        }
        for (final row in run.skip(keepRowRepeats)) {
          final finding = inRow[row];
          if (finding != null && protectedIndices.contains(row)) {
            issues.add(finding);
          }
        }
      }
      index = end;
    }
    return LyricAsrLoopPlan(List.unmodifiable(issues));
  }

  /// How many rows the findings in [document] would rewrite or delete;
  /// used by the draft health hints.
  int loopRowCount(LyricDocument document) {
    final plan = this.plan(document);
    var rows = 0;
    for (final issue in plan.issues) {
      rows += switch (issue.kind) {
        LyricAsrLoopKind.inRowRepeat => 1,
        LyricAsrLoopKind.repeatedRows => issue.removedIndices.length,
      };
    }
    return rows;
  }

  bool _isStrong(LyricAsrLoopRun run) =>
      run.repeats >=
      (run.singleCharacter ? strongSingleRepeats : strongUnitRepeats);

  /// The text's sung content as a comparison key: tokens lower-cased and
  /// joined, punctuation and spacing dropped.
  String rowKey(String text) =>
      tokens(text).map((token) => token.key).join('\u0001');

  /// The loops in [text], left to right, not overlapping.
  List<LyricAsrLoopRun> loops(String text) {
    final list = tokens(text);
    final runs = <LyricAsrLoopRun>[];
    var index = 0;
    while (index < list.length) {
      var bestPeriod = 0;
      var bestRepeats = 0;
      for (
        var period = 1;
        period <= maxUnitTokens && index + period * 2 <= list.length;
        period++
      ) {
        var repeats = 1;
        while (_repeatsAt(list, index, period, repeats)) {
          repeats++;
        }
        final single = period == 1 && list[index].character;
        final needed = single ? minSingleRepeats : minUnitRepeats;
        if (repeats < needed) continue;
        // Most tokens covered wins; a shorter unit wins ties, so `啊啊啊…`
        // is one character repeated rather than two characters.
        if (period * repeats > bestPeriod * bestRepeats) {
          bestPeriod = period;
          bestRepeats = repeats;
        }
      }
      if (bestPeriod == 0) {
        index++;
        continue;
      }
      final single = bestPeriod == 1 && list[index].character;
      final keep = single ? keepSingleRepeats : keepUnitRepeats;
      final last = index + bestPeriod * bestRepeats - 1;
      final keptLast = index + bestPeriod * keep - 1;
      runs.add(
        LyricAsrLoopRun(
          unit: text.substring(
            list[index].start,
            list[index + bestPeriod - 1].end,
          ),
          repeats: bestRepeats,
          kept: keep,
          singleCharacter: single,
          start: list[index].start,
          end: list[last].end,
          keptEnd: list[keptLast].end,
        ),
      );
      index = last + 1;
    }
    return runs;
  }

  bool _repeatsAt(
    List<LyricLoopToken> list,
    int start,
    int period,
    int repeats,
  ) {
    final from = start + period * repeats;
    if (from + period > list.length) return false;
    for (var offset = 0; offset < period; offset++) {
      if (list[from + offset].key != list[start + offset].key) return false;
    }
    return true;
  }

  /// [text] with every run cut down to its kept repeats; the text before,
  /// between and after the runs is unchanged.
  String collapse(String text, List<LyricAsrLoopRun> runs) {
    if (runs.isEmpty) return text;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final run in runs) {
      buffer.write(text.substring(cursor, run.keptEnd));
      cursor = run.end;
    }
    buffer.write(text.substring(cursor));
    return buffer.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  /// The sung tokens of [text] with their UTF-16 ranges.
  List<LyricLoopToken> tokens(String text) {
    final result = <LyricLoopToken>[];
    var offset = 0;
    var wordStart = -1;
    void closeWord(int end) {
      if (wordStart < 0) return;
      // A trailing apostrophe (lovin') is not part of the word.
      while (end > wordStart &&
          (text.codeUnitAt(end - 1) == 0x27 ||
              text.codeUnitAt(end - 1) == 0x2019)) {
        end--;
      }
      final word = text.substring(wordStart, end);
      result.add(
        LyricLoopToken(key: word.toLowerCase(), start: wordStart, end: end),
      );
      wordStart = -1;
    }

    for (final rune in text.runes) {
      final width = rune > 0xffff ? 2 : 1;
      final character = String.fromCharCode(rune);
      final sung = structure.sungWeight(character) > 0;
      if (!sung) {
        // An apostrophe inside a Latin word keeps it together (don't).
        final joiner = (rune == 0x27 || rune == 0x2019) && wordStart >= 0;
        if (!joiner) closeWord(offset);
      } else if (structure.sungWeight(character) >= 1) {
        closeWord(offset);
        result.add(
          LyricLoopToken(
            key: character,
            start: offset,
            end: offset + width,
            character: true,
          ),
        );
      } else if (wordStart < 0) {
        wordStart = offset;
      }
      offset += width;
    }
    closeWord(offset);
    return result;
  }
}

/// One sung token of a row: a character of a spaceless script or a word.
class LyricLoopToken {
  final String key;
  final int start;
  final int end;

  /// A single character of a spaceless script rather than a word.
  final bool character;

  const LyricLoopToken({
    required this.key,
    required this.start,
    required this.end,
    this.character = false,
  });
}
