import '../../../project/domain/models/lyric_document.dart';
import 'lyric_asr_loop_detector.dart';
import 'lyric_indexed_review_metadata.dart';
import 'lyric_manual_edit_marker_service.dart';

/// What kind of finding [LyricMissedRepeatDetector] reports.
enum LyricMissedRepeatKind {
  /// Several words of a row start at the same instant: the forced aligner
  /// could not place them. The karaoke highlight jumps, and the row's start
  /// is often early too: the aligner put the words where it lost the vocal.
  crowdedWords,

  /// One word of a row lasts longer than any sung word does. The aligner
  /// stretched it over singing it could not place (often a chant the
  /// recogniser shortened) or over an intro or interlude. A stretched first
  /// word means the row starts too early, a stretched last word that it ends
  /// too late; in the middle, lyrics are probably missing.
  stretchedWord,

  /// A chant row (vocables, a phrase sung back to back, or a refrain) is
  /// followed by a long stretch without lyrics. Recognisers shorten chants
  /// they hear many times, so the singing may go on where the draft is empty.
  gapAfterChant,
}

/// Where in its row a stretched word sits.
enum LyricStretchedWordPosition { first, middle, last }

/// Why a row counts as a chant.
enum LyricChantReason {
  /// Mostly vocables: oh, whoa, yeah, la, na, 啦, 哦, 呜…
  vocables,

  /// A short phrase sung back to back in the row ("find that fire find that
  /// fire").
  selfRepeat,

  /// The same short row occurs three or more times in the song.
  refrain,
}

/// One finding of [LyricMissedRepeatDetector].
class LyricMissedRepeatIssue {
  final LyricMissedRepeatKind kind;

  /// The row the finding is about.
  final int index;

  /// [LyricMissedRepeatKind.crowdedWords]: how many words share the instant.
  final int crowdedCount;

  /// [LyricMissedRepeatKind.crowdedWords]: the shared instant.
  final Duration crowdedAt;

  /// [LyricMissedRepeatKind.crowdedWords]: the crowded words include the
  /// row's first word, so the row's start time is suspect as well.
  final bool crowdedAtStart;

  /// [LyricMissedRepeatKind.stretchedWord]: the word and where it sits.
  final int wordIndex;
  final String wordText;
  final LyricStretchedWordPosition? position;

  /// [LyricMissedRepeatKind.stretchedWord] at the row's start or end: the
  /// row span after trimming the word to a sung length; null in the middle.
  final Duration? proposedStart;
  final Duration? proposedEnd;

  /// [LyricMissedRepeatKind.gapAfterChant]: why the row counts as a chant.
  final LyricChantReason? reason;

  /// The stretch worth listening to: the empty gap after a chant row (from
  /// its end to the next row's start or the end of the audio), or the span
  /// of a stretched word.
  final Duration spanStart;
  final Duration spanEnd;

  /// The gap runs to the end of the audio rather than to another row.
  final bool toAudioEnd;

  /// The row after the gap has the same text: the chant resumes, so it
  /// probably went on through the gap.
  final bool resumes;

  /// [LyricMissedRepeatKind.gapAfterChant]: copies of the chant row that fit
  /// the gap back to back, most first. The fix inserts a prefix of them.
  final List<LyricLine> fill;

  /// The fix would change a hand-edited row, so it is only listed.
  final bool protected;

  const LyricMissedRepeatIssue._({
    required this.kind,
    required this.index,
    this.crowdedCount = 0,
    this.crowdedAt = Duration.zero,
    this.crowdedAtStart = false,
    this.wordIndex = -1,
    this.wordText = '',
    this.position,
    this.proposedStart,
    this.proposedEnd,
    this.reason,
    this.spanStart = Duration.zero,
    this.spanEnd = Duration.zero,
    this.toAudioEnd = false,
    this.resumes = false,
    this.fill = const [],
    this.protected = false,
  });

  /// Length of [spanStart]–[spanEnd].
  Duration get span => spanEnd - spanStart;

  /// Whether applying the finding changes anything.
  bool get fixable => switch (kind) {
    LyricMissedRepeatKind.crowdedWords => !protected,
    LyricMissedRepeatKind.stretchedWord =>
      !protected && (proposedStart != null || proposedEnd != null),
    LyricMissedRepeatKind.gapAfterChant => fill.isNotEmpty,
  };
}

/// The findings for a document and how to apply a selection of them.
class LyricMissedRepeatPlan {
  final List<LyricMissedRepeatIssue> issues;

  const LyricMissedRepeatPlan(this.issues);

  static const LyricMissedRepeatPlan empty = LyricMissedRepeatPlan([]);

  /// Positions in [issues] that can be applied.
  List<int> get fixablePositions => [
    for (var i = 0; i < issues.length; i++)
      if (issues[i].fixable) i,
  ];

  /// Positions selected by default: clearing crowded word timing and
  /// trimming a stretched first word, which are wrong whatever the audio
  /// holds. A stretched last word may be a held note, and filling a gap
  /// needs listening first.
  List<int> get defaultPositions => [
    for (var i = 0; i < issues.length; i++)
      if (issues[i].fixable && isDefault(issues[i])) i,
  ];

  static bool isDefault(LyricMissedRepeatIssue issue) => switch (issue.kind) {
    LyricMissedRepeatKind.crowdedWords => true,
    LyricMissedRepeatKind.stretchedWord =>
      issue.position == LyricStretchedWordPosition.first,
    LyricMissedRepeatKind.gapAfterChant => false,
  };

  /// Rows a gap finding inserts: [fillCounts] when given for its position,
  /// otherwise every row that fits.
  int fillCountFor(int position, Map<int, int> fillCounts) {
    final fill = issues[position].fill;
    final wanted = fillCounts[position] ?? fill.length;
    return wanted < 0 ? 0 : (wanted > fill.length ? fill.length : wanted);
  }

  /// How many rows a selection clears word timing on, re-times and inserts.
  ({int cleared, int retimed, int inserted}) countFor(
    Set<int> positions, {
    Map<int, int> fillCounts = const {},
  }) {
    var cleared = 0;
    var retimed = 0;
    var inserted = 0;
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      if (!issue.fixable) continue;
      switch (issue.kind) {
        case LyricMissedRepeatKind.crowdedWords:
          cleared++;
        case LyricMissedRepeatKind.stretchedWord:
          retimed++;
        case LyricMissedRepeatKind.gapAfterChant:
          inserted += fillCountFor(position, fillCounts);
      }
    }
    return (cleared: cleared, retimed: retimed, inserted: inserted);
  }

  /// [document] with the selected findings applied: crowded word timing
  /// cleared (export then spreads the row's words evenly), stretched edge
  /// words trimmed together with the row's start or end, and chant copies
  /// inserted after their rows. Existing rows keep their ids; inserted rows
  /// get fresh ids, and row-indexed review data follows the rows it belongs
  /// to.
  LyricDocument applyTo(
    LyricDocument document,
    Set<int> positions, {
    Map<int, int> fillCounts = const {},
    LyricManualEditMarkerService markers = const LyricManualEditMarkerService(),
  }) {
    final clear = <int>{};
    final trims = <int, List<LyricMissedRepeatIssue>>{};
    final inserts = <int, List<LyricLine>>{};
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final issue = issues[position];
      if (!issue.fixable || issue.index >= document.lines.length) continue;
      switch (issue.kind) {
        case LyricMissedRepeatKind.crowdedWords:
          clear.add(issue.index);
        case LyricMissedRepeatKind.stretchedWord:
          (trims[issue.index] ??= []).add(issue);
        case LyricMissedRepeatKind.gapAfterChant:
          final count = fillCountFor(position, fillCounts);
          if (count > 0) inserts[issue.index] = issue.fill.sublist(0, count);
      }
    }
    if (clear.isEmpty && trims.isEmpty && inserts.isEmpty) return document;

    final lines = <LyricLine>[];
    final newIndexOf = <int, int?>{};
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      newIndexOf[index] = lines.length;
      var updated = line;
      for (final trim in trims[index] ?? const <LyricMissedRepeatIssue>[]) {
        updated = _trim(updated, trim);
      }
      if (clear.contains(index)) updated = updated.copyWith(words: const []);
      lines.add(updated);
      lines.addAll(inserts[index] ?? const []);
    }
    return markers.assignMissingLineIds(
      document.copyWith(
        lines: lines,
        metadata: inserts.isEmpty
            ? document.metadata
            : LyricIndexedReviewMetadata.remapped(
                document.metadata,
                (index) => newIndexOf[index],
              ),
      ),
    );
  }

  /// [line] with a stretched first or last word cut down to its proposed
  /// span; the word moves with the row edge so its timing stays inside.
  static LyricLine _trim(LyricLine line, LyricMissedRepeatIssue issue) {
    final words = [...line.words];
    if (issue.wordIndex < 0 || issue.wordIndex >= words.length) return line;
    final word = words[issue.wordIndex];
    final start = issue.proposedStart;
    final end = issue.proposedEnd;
    if (start != null && start < line.endTime) {
      words[issue.wordIndex] = LyricWordTiming(
        text: word.text,
        start: start,
        end: word.end,
      );
      return line.copyWith(startTime: start, words: words);
    }
    if (end != null && end > line.startTime) {
      words[issue.wordIndex] = LyricWordTiming(
        text: word.text,
        start: word.start,
        end: end,
      );
      return line.copyWith(endTime: end, words: words);
    }
    return line;
  }

  /// Row to select after applying: the first affected row. Rows before it
  /// are untouched, so its index does not move.
  int? selectionAfterApply(Set<int> positions) {
    int? first;
    for (final position in positions) {
      if (position < 0 || position >= issues.length) continue;
      final index = issues[position].index;
      if (first == null || index < first) first = index;
    }
    return first;
  }
}

/// Finds places where a recognised draft probably dropped repeated singing:
/// outro chants, backing vocals and refrains sung many times.
///
/// Recognisers write a chant they hear over and over a few times at most,
/// and the forced aligner then has fewer words than the audio holds. Three
/// traces of that are visible in the draft without the audio:
///
/// * **Crowded word timing**: at least [minCrowdedWords] words of a row start
///   within [crowdWindow] of each other. That is the aligner giving up, not
///   singing. The fix clears the row's word timing so karaoke export spreads
///   the words over the row; it is selected by default. When the crowded
///   words open the row, the row itself is probably timed early. (Drafts
///   recognised since zero-length aligner words are repaired rarely show
///   this; older drafts and other engines do.)
/// * **Stretched word**: one word lasting at least [stretchedWordLength].
///   Measured on real songs, the aligner stretches a word over a chant it
///   could not place (24.5 s of "fire" where "whoa, I'm paddling on" was
///   sung) or over an intro (the first word starting 12–25 s early). A
///   stretched first word is trimmed to [edgeWordLength] before its end,
///   moving the row's start (selected by default); a stretched last word is
///   trimmed after its start, moving the row's end (not selected: it may be
///   a held note); a stretched middle word can only be listened to.
/// * **Gap after a chant**: a chant row followed by at least [minGap]
///   without lyrics, either in the last part of the song
///   ([lateShare] of the way from the first row to the end) or with the same
///   chant resuming after the gap. Mid-song gaps after a chant are usually
///   instrumental breaks and are not reported. The fix inserts copies of the
///   chant row back to back into the gap, at most [maxFillRows], timed like
///   the original; it is never selected by default because only listening
///   tells whether the gap is sung. Inserted rows are best re-timed with
///   tap-to-sync.
///
/// A chant is a row of mostly vocables (at least [vocableShare] of its sung
/// tokens), a row whose tokens are mostly one short phrase sung back to back,
/// or a short row that occurs at least [minRefrainCount] times in the song.
class LyricMissedRepeatDetector {
  const LyricMissedRepeatDetector({
    this.tokenizer = const LyricAsrLoopDetector(),
    this.crowdWindow = const Duration(milliseconds: 30),
    this.minCrowdedWords = 5,
    this.stretchedWordLength = const Duration(seconds: 6),
    this.edgeWordLength = const Duration(milliseconds: 800),
    this.minGap = const Duration(seconds: 8),
    this.lateShare = 0.6,
    this.vocableShare = 0.6,
    this.minRefrainCount = 3,
    this.maxRefrainTokens = 10,
    this.maxFillRows = 8,
    this.fillMargin = const Duration(milliseconds: 300),
  });

  /// Supplies the sung tokens of a row (Han characters, kana and Hangul
  /// syllables one by one, Latin words whole).
  final LyricAsrLoopDetector tokenizer;
  final Duration crowdWindow;

  /// Measured on real Qwen alignments, runs of three or four words at one
  /// instant are common and harmless; five or more mark an unplaced chant.
  final int minCrowdedWords;

  /// Sung words rarely exceed four seconds even when held; the aligner's
  /// stretched words in the measured songs ran 6.6–25.6 s.
  final Duration stretchedWordLength;

  /// The length a trimmed stretched edge word keeps.
  final Duration edgeWordLength;

  final Duration minGap;
  final double lateShare;
  final double vocableShare;
  final int minRefrainCount;
  final int maxRefrainTokens;
  final int maxFillRows;

  /// Inserted rows end at least this long before the next row or the end of
  /// the audio.
  final Duration fillMargin;

  /// Every finding in [document], in row order. [audioDuration] lets a gap
  /// after the last row count; without it the last row is never reported.
  LyricMissedRepeatPlan plan(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
    Duration? audioDuration,
  }) {
    final lines = document.lines;
    if (lines.isEmpty) return LyricMissedRepeatPlan.empty;
    final keys = [for (final line in lines) tokenizer.rowKey(line.text)];
    final keyCounts = <String, int>{};
    for (final key in keys) {
      if (key.isNotEmpty) keyCounts[key] = (keyCounts[key] ?? 0) + 1;
    }

    var firstStart = lines.first.startTime;
    var lastEnd = lines.first.endTime;
    for (final line in lines) {
      if (line.startTime < firstStart) firstStart = line.startTime;
      if (line.endTime > lastEnd) lastEnd = line.endTime;
    }
    final songEnd = audioDuration != null && audioDuration > lastEnd
        ? audioDuration
        : lastEnd;
    final lateFrom =
        firstStart +
        Duration(
          microseconds:
              ((songEnd - firstStart).inMicroseconds * lateShare).round(),
        );
    final pause = typicalPause(document);

    final issues = <LyricMissedRepeatIssue>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final crowded = crowdedRun(line.words);
      if (crowded != null) {
        issues.add(
          LyricMissedRepeatIssue._(
            kind: LyricMissedRepeatKind.crowdedWords,
            index: index,
            crowdedCount: crowded.count,
            crowdedAt: line.words[crowded.start].start,
            crowdedAtStart: crowded.start == 0,
            protected: protectedIndices.contains(index),
            spanStart: line.words[crowded.start].start,
            spanEnd: line.endTime,
          ),
        );
      }

      final protected = protectedIndices.contains(index);
      for (var word = 0; word < line.words.length; word++) {
        final timing = line.words[word];
        if (timing.end - timing.start < stretchedWordLength) continue;
        // Word times outside the row are from before the row was moved;
        // their span says nothing about the row's current timing.
        if (timing.start < line.startTime - crowdWindow ||
            timing.end > line.endTime + crowdWindow) {
          continue;
        }
        issues.add(_stretched(line, index, word, protected: protected));
      }

      final reason = chantReason(line.text, keyCounts[keys[index]] ?? 0);
      if (reason == null || line.endTime <= line.startTime) continue;
      final isLast = index == lines.length - 1;
      if (isLast && (audioDuration == null || audioDuration <= line.endTime)) {
        continue;
      }
      final gapEnd = isLast ? audioDuration! : lines[index + 1].startTime;
      if (gapEnd - line.endTime < minGap) continue;
      final resumes = !isLast && keys[index + 1] == keys[index];
      final late = line.startTime >= lateFrom;
      if (!late && !resumes) continue;
      // A refrain is only a chant where songs repeat it: at the end.
      if (reason == LyricChantReason.refrain && !late) continue;

      issues.add(
        LyricMissedRepeatIssue._(
          kind: LyricMissedRepeatKind.gapAfterChant,
          index: index,
          reason: reason,
          spanStart: line.endTime,
          spanEnd: gapEnd,
          toAudioEnd: isLast,
          resumes: resumes,
          fill: _fill(
            line,
            gapEnd,
            period: _period(lines, keys, index, pause),
          ),
        ),
      );
    }
    return LyricMissedRepeatPlan(List.unmodifiable(issues));
  }

  /// How many findings [plan] reports without the audio length; used by the
  /// draft health hints.
  int spotCount(LyricDocument document) => plan(document).issues.length;

  LyricMissedRepeatIssue _stretched(
    LyricLine line,
    int index,
    int word, {
    required bool protected,
  }) {
    final timing = line.words[word];
    final isFirst = word == 0;
    final isLast = word == line.words.length - 1;
    final position = isFirst
        ? LyricStretchedWordPosition.first
        : (isLast
              ? LyricStretchedWordPosition.last
              : LyricStretchedWordPosition.middle);
    Duration? proposedStart;
    Duration? proposedEnd;
    if (position == LyricStretchedWordPosition.first) {
      final start = timing.end - edgeWordLength;
      // Only a word that opens the row moves the row's start.
      if (timing.start <= line.startTime + crowdWindow &&
          start > line.startTime &&
          start < line.endTime) {
        proposedStart = start;
      }
    } else if (position == LyricStretchedWordPosition.last) {
      final end = timing.start + edgeWordLength;
      if (timing.end >= line.endTime - crowdWindow &&
          end < line.endTime &&
          end > line.startTime) {
        proposedEnd = end;
      }
    }
    return LyricMissedRepeatIssue._(
      kind: LyricMissedRepeatKind.stretchedWord,
      index: index,
      wordIndex: word,
      wordText: timing.text,
      position: position,
      proposedStart: proposedStart,
      proposedEnd: proposedEnd,
      spanStart: timing.start,
      spanEnd: timing.end,
      protected: protected,
    );
  }

  /// The longest run of words starting within [crowdWindow] of the run's
  /// first word, or null when no run reaches [minCrowdedWords].
  ({int start, int count})? crowdedRun(List<LyricWordTiming> words) {
    ({int start, int count})? best;
    var start = 0;
    while (start < words.length) {
      var end = start + 1;
      while (end < words.length &&
          (words[end].start - words[start].start).abs() <= crowdWindow) {
        end++;
      }
      final count = end - start;
      if (count >= minCrowdedWords && (best == null || count > best.count)) {
        best = (start: start, count: count);
      }
      start = end;
    }
    return best;
  }

  /// Why [text] counts as a chant, or null. [occurrences] is how often the
  /// row's text occurs in the song.
  LyricChantReason? chantReason(String text, int occurrences) {
    final keys = [for (final token in tokenizer.tokens(text)) token.key];
    if (keys.isEmpty) return null;
    final vocables = keys.where(isVocable).length;
    if (vocables >= keys.length * vocableShare) {
      return LyricChantReason.vocables;
    }
    if (keys.length >= 2 && _selfRepeatCover(keys) * 3 >= keys.length * 2) {
      return LyricChantReason.selfRepeat;
    }
    if (occurrences >= minRefrainCount && keys.length <= maxRefrainTokens) {
      return LyricChantReason.refrain;
    }
    return null;
  }

  /// Tokens covered by the longest back-to-back run of a 1–6 token phrase
  /// repeated at least twice.
  int _selfRepeatCover(List<String> keys) {
    var best = 0;
    for (var start = 0; start < keys.length; start++) {
      for (var period = 1; period <= 6; period++) {
        if (start + period * 2 > keys.length) break;
        var repeats = 1;
        while (start + period * (repeats + 1) <= keys.length) {
          var same = true;
          for (var offset = 0; offset < period; offset++) {
            if (keys[start + period * repeats + offset] !=
                keys[start + offset]) {
              same = false;
              break;
            }
          }
          if (!same) break;
          repeats++;
        }
        if (repeats >= 2 && period * repeats > best) best = period * repeats;
      }
    }
    return best;
  }

  /// Whether a lower-case token is a vocable rather than a word. Latin
  /// tokens are compared with letter runs collapsed (`ooooh` is `oh`,
  /// `yeahhh` is `yeah`) and may chain (`lalala`, `ohoh`).
  static bool isVocable(String token) {
    if (_cjkVocables.contains(token)) return true;
    final collapsed = token.replaceAllMapped(
      RegExp(r'([a-z])\1+'),
      (match) => match.group(1)!,
    );
    return _latinVocables.hasMatch(collapsed);
  }

  static final RegExp _latinVocables = RegExp(
    r'^(?:la|na|da|du|oh|ah|uh|o|whoa|woah|wo|yeah|yea|ye|hey|ha|ho|hm|m|ay|eh|yo|ya|huh)+$',
  );

  static const Set<String> _cjkVocables = {
    '啦', '啊', '哦', '喔', '噢', '呜', '哎', '嘿', '耶', '嗯', '哈', '呀', '唔', //
    '哟', '呦', '嗨', '咿', '呃', '欸', 'ら', 'ラ', 'あ', 'ア', 'お', 'オ', 'う', //
    'ウ', 'な', 'ナ', '라', '아', '오', '나', '예', '워', '우',
  };

  /// The usual silence between consecutive rows of [document]: the median of
  /// the gaps shorter than two seconds, clamped to 150–1000 ms. 400 ms when
  /// the document has none.
  Duration typicalPause(LyricDocument document) {
    final gaps = <int>[];
    final lines = document.lines;
    for (var index = 1; index < lines.length; index++) {
      final gap = lines[index].startTime - lines[index - 1].endTime;
      if (gap > Duration.zero && gap < const Duration(seconds: 2)) {
        gaps.add(gap.inMilliseconds);
      }
    }
    if (gaps.isEmpty) return const Duration(milliseconds: 400);
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    return Duration(milliseconds: median.clamp(150, 1000));
  }

  /// Start-to-start distance of the inserted copies: the distance from the
  /// previous row when it is the same chant, otherwise the row's length plus
  /// the song's usual pause.
  Duration _period(
    List<LyricLine> lines,
    List<String> keys,
    int index,
    Duration pause,
  ) {
    final line = lines[index];
    final length = line.endTime - line.startTime;
    if (index > 0 && keys[index - 1] == keys[index]) {
      final distance = line.startTime - lines[index - 1].startTime;
      if (distance > length) return distance;
    }
    return length + pause;
  }

  List<LyricLine> _fill(LyricLine line, Duration gapEnd, {required Duration period}) {
    final length = line.endTime - line.startTime;
    final fill = <LyricLine>[];
    for (var copy = 1; copy <= maxFillRows; copy++) {
      final start = line.startTime + period * copy;
      final end = start + length;
      if (end > gapEnd - fillMargin) break;
      fill.add(
        LyricLine(
          text: line.text,
          startTime: start,
          endTime: end,
          isChorus: line.isChorus,
          confidence: unscoredConfidencePlaceholder,
          confidenceSource: LyricConfidenceSource.unscored,
        ),
      );
    }
    return List.unmodifiable(fill);
  }
}
