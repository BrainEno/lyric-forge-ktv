import 'chinese_script_tables.dart';

/// The written forms LyricForge can produce.
///
/// OpenCC's "standard" traditional forms (裏, 爲, 着) read as unusual to most
/// readers, so only the two regional traditional standards are offered.
enum ChineseScriptTarget {
  simplified,
  traditionalTaiwan,
  traditionalHongKong;

  bool get isTraditional => this != ChineseScriptTarget.simplified;
}

/// Which script a piece of text is evidently written in.
enum ChineseScriptKind {
  /// No Han characters at all.
  none,

  /// Han characters, but only ones shared by both scripts (我, 你, 心 …).
  neutral,
  simplified,
  traditional,

  /// Characters exclusive to each script in the same text.
  mixed,
}

/// Script evidence counted over one piece of text.
class ChineseScriptProfile {
  final int hanCount;
  final int simplifiedOnlyCount;
  final int traditionalOnlyCount;

  /// Kana or Hangul present: the text is Japanese or Korean, whose kanji and
  /// hanja must never be rewritten into a Chinese standard.
  final bool hasKanaOrHangul;

  const ChineseScriptProfile({
    required this.hanCount,
    required this.simplifiedOnlyCount,
    required this.traditionalOnlyCount,
    required this.hasKanaOrHangul,
  });

  ChineseScriptKind get kind {
    if (hanCount == 0) return ChineseScriptKind.none;
    if (simplifiedOnlyCount > 0 && traditionalOnlyCount > 0) {
      return ChineseScriptKind.mixed;
    }
    if (simplifiedOnlyCount > 0) return ChineseScriptKind.simplified;
    if (traditionalOnlyCount > 0) return ChineseScriptKind.traditional;
    return ChineseScriptKind.neutral;
  }
}

/// Pure-Dart simplified/traditional conversion and comparison folding over the
/// OpenCC dictionaries bundled in [ChineseScriptTables].
///
/// Conversion follows OpenCC's chains: longest phrase match first, then the
/// default character candidate; traditional output is then adjusted to the
/// regional standard. It changes only the written form of a character, never
/// the word, so it does not apply OpenCC's regional vocabulary tables
/// (软件 → 軟體), which would rewrite lyrics.
class ChineseScriptConverter {
  const ChineseScriptConverter();

  /// The lowest code point any table touches; everything below is passed
  /// through without a lookup.
  static const int _firstCjkRune = 0x2e80;

  ChineseScriptTables get _tables => ChineseScriptTables.instance;

  /// The table build, recorded with every conversion so it can be replayed.
  String get revision => _tables.revision;

  /// Comparison key for one code point; identical for the simplified,
  /// traditional and regional forms of the same character.
  int foldRune(int rune) {
    if (rune < _firstCjkRune) return rune;
    return _tables.comparisonFold[rune] ?? rune;
  }

  /// Comparison key for a string. Lossy by design (乾/干 fold together); use
  /// it only to decide whether two texts say the same thing.
  String foldForComparison(String text) {
    if (!_mayContainCjk(text)) return text;
    final output = StringBuffer();
    for (final rune in text.runes) {
      output.writeCharCode(foldRune(rune));
    }
    return output.toString();
  }

  /// Script evidence in [text].
  ChineseScriptProfile profile(String text) {
    var han = 0;
    var simplifiedOnly = 0;
    var traditionalOnly = 0;
    var kanaOrHangul = false;
    if (_mayContainCjk(text)) {
      final tables = _tables;
      for (final rune in text.runes) {
        if (isHanRune(rune)) {
          han++;
          if (tables.simplifiedOnly.contains(rune)) simplifiedOnly++;
          if (tables.traditionalOnly.contains(rune)) traditionalOnly++;
        } else if (isKanaOrHangulRune(rune)) {
          kanaOrHangul = true;
        }
      }
    }
    return ChineseScriptProfile(
      hanCount: han,
      simplifiedOnlyCount: simplifiedOnly,
      traditionalOnlyCount: traditionalOnly,
      hasKanaOrHangul: kanaOrHangul,
    );
  }

  /// Converts to [target]. Text already in the target script passes through,
  /// apart from regional form adjustments when the target is traditional.
  String convert(String text, ChineseScriptTarget target) => switch (target) {
    ChineseScriptTarget.simplified => toSimplified(text),
    ChineseScriptTarget.traditionalTaiwan ||
    ChineseScriptTarget.traditionalHongKong => toTraditional(text, target),
  };

  /// Converts one lyric line to [target], choosing the chain from the line's
  /// own script: a line that is already traditional only gets regional form
  /// adjustments, because running the simplified-to-traditional chain over
  /// it would reinterpret shared characters (台, 只, 里) as simplified.
  String convertLine(String text, ChineseScriptTarget target) {
    if (!target.isTraditional) return toSimplified(text);
    if (profile(text).kind == ChineseScriptKind.traditional) {
      return toRegionalForms(text, target);
    }
    return toTraditional(text, target);
  }

  /// OpenCC tw2s/hk2s: regional forms back to the standard, then t2s.
  String toSimplified(String text) {
    if (!_mayContainCjk(text)) return text;
    final tables = _tables;
    var value = _match(
      text,
      tables.taiwanVariantReversePhrases,
      tables.taiwanVariantsReverse,
    );
    value = _match(
      value,
      tables.hongKongVariantReversePhrases,
      tables.hongKongVariantsReverse,
    );
    return _match(
      value,
      tables.traditionalToSimplifiedPhrases,
      tables.traditionalToSimplified,
    );
  }

  /// OpenCC s2tw/s2hk without regional vocabulary.
  String toTraditional(String text, ChineseScriptTarget target) {
    assert(target.isTraditional, 'Use toSimplified for simplified output.');
    if (!_mayContainCjk(text)) return text;
    final tables = _tables;
    final standard = _match(
      text,
      tables.simplifiedToTraditionalPhrases,
      tables.simplifiedToTraditional,
    );
    return toRegionalForms(standard, target);
  }

  /// OpenCC t2tw/t2hk: adjusts traditional text to the regional standard
  /// (裏 → 裡, 着 → 著) without treating any character as simplified.
  String toRegionalForms(String traditional, ChineseScriptTarget target) {
    if (!_mayContainCjk(traditional)) return traditional;
    final tables = _tables;
    return switch (target) {
      ChineseScriptTarget.simplified => traditional,
      ChineseScriptTarget.traditionalTaiwan => _match(
        traditional,
        tables.taiwanVariantPhrases,
        tables.taiwanVariants,
      ),
      ChineseScriptTarget.traditionalHongKong => _match(
        traditional,
        tables.hongKongVariantPhrases,
        tables.hongKongVariants,
      ),
    };
  }

  /// Forward maximum matching: the longest phrase starting at each position
  /// wins, otherwise the default character candidate is used.
  String _match(String text, ChinesePhraseTable phrases, Map<int, int> chars) {
    final runes = text.runes.toList(growable: false);
    StringBuffer? output;
    var copiedUpTo = 0;
    var index = 0;
    while (index < runes.length) {
      final rune = runes[index];
      if (rune < _firstCjkRune) {
        index++;
        continue;
      }
      String? replacement;
      var consumed = 1;
      if (phrases.firstRunes.contains(rune)) {
        final remaining = runes.length - index;
        final longest = remaining < phrases.maxKeyRunes
            ? remaining
            : phrases.maxKeyRunes;
        for (var length = longest; length >= 2; length--) {
          final candidate = String.fromCharCodes(runes, index, index + length);
          final value = phrases.entries[candidate];
          if (value != null) {
            replacement = value;
            consumed = length;
            break;
          }
        }
      }
      if (replacement == null) {
        final mapped = chars[rune];
        if (mapped != null) replacement = String.fromCharCode(mapped);
      }
      if (replacement != null) {
        output ??= StringBuffer();
        output.write(String.fromCharCodes(runes, copiedUpTo, index));
        output.write(replacement);
        copiedUpTo = index + consumed;
      }
      index += consumed;
    }
    if (output == null) return text;
    output.write(String.fromCharCodes(runes, copiedUpTo, runes.length));
    return output.toString();
  }

  static bool _mayContainCjk(String text) {
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) >= _firstCjkRune) return true;
    }
    return false;
  }

  /// CJK Unified Ideographs, extensions A–J and compatibility ideographs.
  static bool isHanRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xf900 && rune <= 0xfaff) ||
      (rune >= 0x20000 && rune <= 0x323af) ||
      (rune >= 0x323b0 && rune <= 0x3347f);

  static bool isKanaOrHangulRune(int rune) =>
      (rune >= 0x3040 && rune <= 0x30ff) ||
      (rune >= 0x31f0 && rune <= 0x31ff) ||
      (rune >= 0xff66 && rune <= 0xff9f) ||
      (rune >= 0x1100 && rune <= 0x11ff) ||
      (rune >= 0x3130 && rune <= 0x318f) ||
      (rune >= 0xac00 && rune <= 0xd7af);
}
