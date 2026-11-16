import 'lyric_line_structure_service.dart';

/// One highlighted unit of a karaoke row: a Han character, a kana, a Hangul
/// syllable or a Latin word, together with the spaces and punctuation that
/// are displayed with it.
class LyricKaraokeSyllable {
  /// The text as displayed, including attached punctuation and a trailing
  /// space.
  final String text;

  /// When the unit starts to be sung, on the export timeline.
  final Duration start;

  /// How long the unit is highlighted.
  final Duration duration;

  const LyricKaraokeSyllable({
    required this.text,
    required this.start,
    required this.duration,
  });

  Duration get end => start + duration;

  @override
  String toString() => 'LyricKaraokeSyllable($text, $start, $duration)';
}

/// Estimates per-syllable timing inside a timed row.
///
/// Recognition and the editor only know when a row starts and ends, but
/// karaoke formats (word-timed LRC, ASS `\k` tags) want a time for every
/// sung unit. Without word timestamps the best deterministic guess is to
/// spread the row's duration over its units by how long each one takes to
/// sing:
///
/// * every Han character, kana and Hangul syllable is one unit of weight 1;
/// * a run of Latin letters is one word weighted by its vowel groups (a
///   rough syllable count, at least 1), so "beautiful" is not sung four
///   times slower than "love";
/// * a run of digits weighs one unit per digit;
/// * spaces and punctuation weigh nothing and are shown with the unit before
///   them (leading punctuation with the unit after it).
///
/// Durations are rounded to [resolution] with the rounding error carried
/// forward, so the syllables always add up to exactly the row's duration
/// (after rounding the row itself) and never drift.
class LyricKaraokeTimingService {
  const LyricKaraokeTimingService({
    this.resolution = const Duration(milliseconds: 10),
  });

  /// The smallest step a karaoke tag can express. ASS `\k` counts
  /// centiseconds, so 10 ms is the default.
  final Duration resolution;

  /// Splits [text] into display units with their singing weights.
  List<({String text, double weight})> units(String text) {
    final runes = text.runes.toList(growable: false);
    final result = <({String text, double weight})>[];
    var pendingPrefix = StringBuffer();

    void addUnit(String unitText, double weight) {
      result.add((text: '$pendingPrefix$unitText', weight: weight));
      pendingPrefix = StringBuffer();
    }

    void attach(String value) {
      if (result.isEmpty) {
        pendingPrefix.write(value);
        return;
      }
      final last = result.removeLast();
      result.add((text: '${last.text}$value', weight: last.weight));
    }

    var index = 0;
    while (index < runes.length) {
      final rune = runes[index];
      if (LyricLineStructureService.isSpacelessScript(rune) ||
          _isHangul(rune)) {
        addUnit(String.fromCharCode(rune), 1);
        index++;
      } else if (_isLetter(rune)) {
        final start = index;
        while (index < runes.length &&
            (_isLetter(runes[index]) || _isWordJoiner(runes, index))) {
          index++;
        }
        final word = String.fromCharCodes(runes.sublist(start, index));
        addUnit(word, _syllableCount(word).toDouble());
      } else if (_isDigit(rune)) {
        final start = index;
        while (index < runes.length && _isDigit(runes[index])) {
          index++;
        }
        addUnit(
          String.fromCharCodes(runes.sublist(start, index)),
          (index - start).toDouble(),
        );
      } else {
        attach(String.fromCharCode(rune));
        index++;
      }
    }
    if (pendingPrefix.isNotEmpty) {
      // Text with no sung unit at all: keep it as one silent unit so the
      // row still shows something.
      result.add((text: pendingPrefix.toString(), weight: 0));
    }
    return result;
  }

  /// The row [text] sung from [start] to [end], one entry per unit.
  ///
  /// Returns an empty list for text without any characters. A row whose end
  /// is not after its start gets every unit at [start] with zero duration;
  /// callers are expected to pass a usable end (export cues always have
  /// one).
  List<LyricKaraokeSyllable> syllables(
    String text,
    Duration start,
    Duration end,
  ) {
    final parts = units(text);
    if (parts.isEmpty) return const [];
    final step = resolution.inMicroseconds;
    final startSteps = (start.inMicroseconds / step).round();
    final endSteps = (end.inMicroseconds / step).round();
    final totalSteps = endSteps > startSteps ? endSteps - startSteps : 0;
    final totalWeight = parts.fold<double>(0, (sum, part) => sum + part.weight);

    final result = <LyricKaraokeSyllable>[];
    var consumedWeight = 0.0;
    var consumedSteps = 0;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      int steps;
      if (index == parts.length - 1) {
        steps = totalSteps - consumedSteps;
      } else if (totalWeight <= 0) {
        // Only silent units: share the time evenly.
        final target = (totalSteps * (index + 1) / parts.length).round();
        steps = target - consumedSteps;
      } else {
        consumedWeight += part.weight;
        final target = (totalSteps * consumedWeight / totalWeight).round();
        steps = target - consumedSteps;
      }
      if (steps < 0) steps = 0;
      result.add(
        LyricKaraokeSyllable(
          text: part.text,
          start: Duration(microseconds: (startSteps + consumedSteps) * step),
          duration: Duration(microseconds: steps * step),
        ),
      );
      consumedSteps += steps;
    }
    return result;
  }

  /// A rough English syllable count: groups of vowels, a silent final "e"
  /// dropped, at least 1.
  static int _syllableCount(String word) {
    final lower = word.toLowerCase();
    var groups = 0;
    var inVowel = false;
    for (final rune in lower.runes) {
      final vowel = _isVowel(rune);
      if (vowel && !inVowel) groups++;
      inVowel = vowel;
    }
    if (groups > 1 &&
        lower.endsWith('e') &&
        !lower.endsWith('le') &&
        !lower.endsWith('ee')) {
      groups--;
    }
    return groups < 1 ? 1 : groups;
  }

  static bool _isVowel(int rune) => const {
    0x61, // a
    0x65, // e
    0x69, // i
    0x6f, // o
    0x75, // u
    0x79, // y
    0xe0, 0xe1, 0xe2, 0xe4, 0xe8, 0xe9, 0xea, 0xeb, //
    0xec, 0xed, 0xee, 0xef, 0xf2, 0xf3, 0xf4, 0xf6, //
    0xf9, 0xfa, 0xfb, 0xfc, //
  }.contains(rune);

  /// An apostrophe or hyphen between two letters keeps a word together
  /// ("don't", "rock-n-roll").
  static bool _isWordJoiner(List<int> runes, int index) {
    final rune = runes[index];
    if (rune != 0x27 && rune != 0x2019 && rune != 0x2d) return false;
    return index > 0 &&
        index + 1 < runes.length &&
        _isLetter(runes[index - 1]) &&
        _isLetter(runes[index + 1]);
  }

  static bool _isLetter(int rune) =>
      (rune >= 0x41 && rune <= 0x5a) ||
      (rune >= 0x61 && rune <= 0x7a) ||
      (rune >= 0xc0 && rune <= 0x24f && rune != 0xd7 && rune != 0xf7) ||
      (rune >= 0x370 && rune <= 0x3ff) ||
      (rune >= 0x400 && rune <= 0x4ff);

  static bool _isDigit(int rune) =>
      (rune >= 0x30 && rune <= 0x39) || (rune >= 0xff10 && rune <= 0xff19);

  static bool _isHangul(int rune) =>
      (rune >= 0xac00 && rune <= 0xd7af) || (rune >= 0x1100 && rune <= 0x11ff);
}
