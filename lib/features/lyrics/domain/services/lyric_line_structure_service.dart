import '../../../project/domain/models/lyric_document.dart';
import '../text/chinese_script_converter.dart';

/// Where the boundary time of a split came from.
enum LyricSplitTimingSource {
  /// The paused playhead sat inside the line, so the user marked the break by
  /// ear and that position is used as is.
  playback,

  /// No usable playhead: the line's time span is divided in proportion to how
  /// much is sung on each side of the break.
  textProportion,
}

/// Why a line could not be split.
enum LyricLineSplitFailure {
  /// One side of the break would have no lyric text.
  emptyPart,

  /// The line is too short in time to leave each half a usable duration.
  tooShortToSplit,

  /// No break position was given and the text has no natural break.
  noNaturalBreak,
}

/// A line split into two consecutive rows.
class LyricLineSplit {
  /// The first half. It keeps the original row's id so review evidence and the
  /// audition keep pointing at the row the user was working on.
  final LyricLine first;

  /// The second half. It has no id yet; the caller assigns a fresh one.
  final LyricLine second;

  /// Code-unit offset in the original text where the second half begins.
  final int textOffset;

  final Duration splitTime;
  final LyricSplitTimingSource timingSource;

  const LyricLineSplit({
    required this.first,
    required this.second,
    required this.textOffset,
    required this.splitTime,
    required this.timingSource,
  });
}

/// Either a split or the reason there is none.
class LyricLineSplitResult {
  final LyricLineSplit? split;
  final LyricLineSplitFailure? failure;

  const LyricLineSplitResult.success(LyricLineSplit this.split)
    : failure = null;

  const LyricLineSplitResult.failure(LyricLineSplitFailure this.failure)
    : split = null;

  bool get succeeded => split != null;
}

/// Splits one lyric row into two, or merges two rows into one.
///
/// Speech recognisers segment by pauses, not by lyric lines, so a draft often
/// has one row holding two sung lines, or one sung line cut into a fragment
/// and a remainder. Retyping those by hand means deleting a row and inserting
/// another with guessed timestamps. This service does the structural part
/// precisely and leaves every decision about *where* to the caller:
///
/// * a split never invents text: each half is exactly the original text on
///   its side of the break, minus the whitespace and soft punctuation (，、;)
///   that sat at the break;
/// * the boundary time is the paused playhead when it lies inside the line,
///   otherwise the span is divided by sung weight (one Han, kana or Hangul
///   character counts one, a Latin letter or digit half) — never outside the
///   original span, and never leaving a half shorter than
///   [minimumPartDuration];
/// * a merge keeps the earliest start, the latest end and the weaker of the
///   two confidence scores, so merging cannot make a doubtful row look sure.
///
/// Pure Dart: no Flutter, no I/O, deterministic.
class LyricLineStructureService {
  const LyricLineStructureService({
    this.minimumPartDuration = const Duration(milliseconds: 200),
    this.timeGranularity = const Duration(milliseconds: 10),
  });

  /// Shortest duration either half of a split may have.
  final Duration minimumPartDuration;

  /// Proportional split times are rounded to this step, matching the
  /// centisecond precision of LRC exports.
  final Duration timeGranularity;

  /// The break nearest to the sung middle of [text], as the code-unit offset
  /// where the second half would begin, or null when there is none.
  ///
  /// Whitespace and sentence punctuation are natural breaks; punctuation wins
  /// a near tie because it is the recogniser's own sentence boundary. Text
  /// without such a break can still be split between two Han or kana
  /// characters, but never inside a Latin or Hangul word.
  int? suggestSplitOffset(String text) =>
      _bestBreak(text, allowCharacterBreak: true)?.offset;

  /// Whether [suggestSplitOffset] would find a whitespace or punctuation
  /// break rather than falling back to the middle of a run of characters.
  bool hasNaturalBreak(String text) =>
      _bestBreak(text, allowCharacterBreak: false) != null;

  /// Splits [line] at [textOffset] (a code-unit offset into its text, as a
  /// text field's cursor reports it) or, when that is null, at
  /// [suggestSplitOffset].
  ///
  /// [playbackPosition] is a timeline position (global offset already
  /// removed). It is used as the boundary only when it leaves both halves at
  /// least [minimumPartDuration]; otherwise the time is proportional.
  LyricLineSplitResult split(
    LyricLine line, {
    int? textOffset,
    Duration? playbackPosition,
  }) {
    final text = line.text;
    final offset = textOffset == null
        ? suggestSplitOffset(text)
        : _safeOffset(text, textOffset);
    if (offset == null) {
      return const LyricLineSplitResult.failure(
        LyricLineSplitFailure.noNaturalBreak,
      );
    }

    final left = _trimBreakEnd(text.substring(0, offset));
    final right = _trimBreakStart(text.substring(offset));
    if (left.isEmpty || right.isEmpty) {
      return const LyricLineSplitResult.failure(
        LyricLineSplitFailure.emptyPart,
      );
    }

    final duration = line.endTime - line.startTime;
    if (duration < minimumPartDuration * 2) {
      return const LyricLineSplitResult.failure(
        LyricLineSplitFailure.tooShortToSplit,
      );
    }
    final earliest = line.startTime + minimumPartDuration;
    final latest = line.endTime - minimumPartDuration;

    late final Duration splitTime;
    late final LyricSplitTimingSource source;
    if (playbackPosition != null &&
        playbackPosition >= earliest &&
        playbackPosition <= latest) {
      splitTime = playbackPosition;
      source = LyricSplitTimingSource.playback;
    } else {
      var leftWeight = sungWeight(left);
      var rightWeight = sungWeight(right);
      if (leftWeight + rightWeight <= 0) {
        leftWeight = left.length.toDouble();
        rightWeight = right.length.toDouble();
      }
      final ratio = leftWeight / (leftWeight + rightWeight);
      final raw = line.startTime.inMicroseconds + duration.inMicroseconds * ratio;
      final step = timeGranularity.inMicroseconds <= 0
          ? 1
          : timeGranularity.inMicroseconds;
      var proposed = Duration(microseconds: (raw / step).round() * step);
      if (proposed < earliest) proposed = earliest;
      if (proposed > latest) proposed = latest;
      splitTime = proposed;
      source = LyricSplitTimingSource.textProportion;
    }

    return LyricLineSplitResult.success(
      LyricLineSplit(
        first: line.copyWith(text: left, endTime: splitTime),
        second: LyricLine(
          text: right,
          startTime: splitTime,
          endTime: line.endTime,
          isChorus: line.isChorus,
          confidence: line.confidence,
          confidenceSource: line.confidenceSource,
        ),
        textOffset: offset,
        splitTime: splitTime,
        timingSource: source,
      ),
    );
  }

  /// [first] and [second] as one row. The result keeps [first]'s id.
  LyricLine merge(LyricLine first, LyricLine second) {
    final start = first.startTime <= second.startTime
        ? first.startTime
        : second.startTime;
    final end = first.endTime >= second.endTime
        ? first.endTime
        : second.endTime;

    // The weaker real score wins; a placeholder never outranks a real score.
    late final int confidence;
    late final LyricConfidenceSource source;
    if (first.hasConfidenceScore && second.hasConfidenceScore) {
      final weaker = first.confidence <= second.confidence ? first : second;
      confidence = weaker.confidence;
      source =
          first.confidenceSource == LyricConfidenceSource.heuristic ||
              second.confidenceSource == LyricConfidenceSource.heuristic
          ? LyricConfidenceSource.heuristic
          : weaker.confidenceSource;
    } else if (first.hasConfidenceScore || second.hasConfidenceScore) {
      final scored = first.hasConfidenceScore ? first : second;
      confidence = scored.confidence;
      source = scored.confidenceSource;
    } else {
      confidence = first.confidence <= second.confidence
          ? first.confidence
          : second.confidence;
      source = LyricConfidenceSource.unscored;
    }

    return LyricLine(
      text: joinText(first.text, second.text),
      startTime: start,
      endTime: end,
      isChorus: first.isChorus || second.isChorus,
      confidence: confidence,
      confidenceSource: source,
      id: first.id,
    );
  }

  /// Joins two lyric fragments the way the language writes them: directly
  /// between Han or kana characters, with one space otherwise.
  String joinText(String first, String second) {
    final left = first.trim();
    final right = second.trim();
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    final last = left.runes.last;
    final next = right.runes.first;
    final direct =
        (isSpacelessScript(last) || _isCjkPunctuation(last)) &&
        (isSpacelessScript(next) || _isCjkPunctuation(next));
    return direct ? '$left$right' : '$left $right';
  }

  /// How much is sung in [text], in Han-character units. Used for display
  /// length checks and for proportional split times.
  double sungWeight(String text) {
    var weight = 0.0;
    for (final rune in text.runes) {
      weight += _runeWeight(rune);
    }
    return weight;
  }

  static double _runeWeight(int rune) {
    if (isSpacelessScript(rune) || _isHangul(rune)) return 1;
    if (_isWhitespace(rune) || _isPunctuation(rune)) return 0;
    return 0.5;
  }

  _Break? _bestBreak(String text, {required bool allowCharacterBreak}) {
    final runes = text.runes.toList(growable: false);
    if (runes.length < 2) return null;
    final offsets = List<int>.filled(runes.length + 1, 0);
    final before = List<double>.filled(runes.length + 1, 0);
    for (var i = 0; i < runes.length; i++) {
      offsets[i + 1] = offsets[i] + (runes[i] > 0xffff ? 2 : 1);
      before[i + 1] = before[i] + _runeWeight(runes[i]);
    }
    final total = before[runes.length];
    if (total < 2) return null;
    final middle = total / 2;

    _Break? best;
    void consider(int runeIndex, {required bool punctuation}) {
      final leftWeight = before[runeIndex];
      final rightWeight = total - leftWeight;
      // Each side must carry at least one sung character.
      if (leftWeight < 1 || rightWeight < 1) return;
      var distance = (leftWeight - middle).abs();
      if (punctuation) distance -= 0.5;
      if (best == null || distance < best!.distance) {
        best = _Break(offsets[runeIndex], distance);
      }
    }

    // Separator runs: the second half begins at the first sung rune after it.
    var i = 0;
    while (i < runes.length) {
      if (!_isSeparator(runes[i])) {
        i++;
        continue;
      }
      var punctuation = false;
      final runStart = i;
      while (i < runes.length && _isSeparator(runes[i])) {
        if (!_isWhitespace(runes[i])) punctuation = true;
        i++;
      }
      if (runStart > 0 && i < runes.length) {
        consider(i, punctuation: punctuation);
      }
    }
    if (best != null || !allowCharacterBreak) return best;

    for (var index = 1; index < runes.length; index++) {
      if (isSpacelessScript(runes[index - 1]) &&
          isSpacelessScript(runes[index])) {
        consider(index, punctuation: false);
      }
    }
    return best;
  }

  /// Keeps a cursor offset inside the text and off a surrogate pair's middle.
  static int _safeOffset(String text, int offset) {
    if (offset <= 0) return 0;
    if (offset >= text.length) return text.length;
    final unit = text.codeUnitAt(offset);
    final isLowSurrogate = unit >= 0xdc00 && unit <= 0xdfff;
    return isLowSurrogate ? offset + 1 : offset;
  }

  static String _trimBreakEnd(String text) {
    var runes = text.trimRight().runes.toList();
    while (runes.isNotEmpty &&
        (_isSoftBreakPunctuation(runes.last) || _isWhitespace(runes.last))) {
      runes = runes.sublist(0, runes.length - 1);
    }
    return String.fromCharCodes(runes);
  }

  static String _trimBreakStart(String text) {
    var runes = text.trimLeft().runes.toList();
    while (runes.isNotEmpty &&
        (_isSoftBreakPunctuation(runes.first) || _isWhitespace(runes.first))) {
      runes = runes.sublist(1);
    }
    return String.fromCharCodes(runes);
  }

  /// Han characters and Japanese kana: scripts written without spaces.
  static bool isSpacelessScript(int rune) {
    if (ChineseScriptConverter.isHanRune(rune)) return true;
    return (rune >= 0x3040 && rune <= 0x30ff) ||
        (rune >= 0x31f0 && rune <= 0x31ff);
  }

  /// Punctuation that only joins clauses and is dropped at a split.
  static bool _isSoftBreakPunctuation(int rune) => const {
    0x2c, // ,
    0x3b, // ;
    0x3a, // :
    0x3001, // 、
    0xff0c, // ，
    0xff1b, // ；
    0xff1a, // ：
    0x2f, // /
    0x7c, // |
  }.contains(rune);

  static bool _isSeparator(int rune) =>
      _isWhitespace(rune) ||
      _isSoftBreakPunctuation(rune) ||
      const {
        0x2e, // .
        0x21, // !
        0x3f, // ?
        0x3002, // 。
        0xff01, // ！
        0xff1f, // ？
        0x2026, // …
        0xff0e, // ．
      }.contains(rune);

  static bool _isCjkPunctuation(int rune) =>
      (rune >= 0x3000 && rune <= 0x303f) ||
      (rune >= 0xff00 && rune <= 0xff0f) ||
      (rune >= 0xff1a && rune <= 0xff20);

  static bool _isHangul(int rune) =>
      (rune >= 0xac00 && rune <= 0xd7af) || (rune >= 0x1100 && rune <= 0x11ff);

  static bool _isWhitespace(int rune) =>
      rune == 0x20 ||
      rune == 0x09 ||
      rune == 0x0a ||
      rune == 0x0d ||
      rune == 0xa0 ||
      rune == 0x3000;

  static bool _isPunctuation(int rune) {
    if (rune < 0x80) {
      return !((rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5a) ||
          (rune >= 0x61 && rune <= 0x7a));
    }
    return _isCjkPunctuation(rune) ||
        (rune >= 0x2010 && rune <= 0x205e) ||
        (rune >= 0x2600 && rune <= 0x26ff);
  }
}

class _Break {
  final int offset;
  final double distance;

  const _Break(this.offset, this.distance);
}
