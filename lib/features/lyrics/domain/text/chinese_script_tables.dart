import 'chinese_script_data.g.dart' as data;

/// A phrase dictionary prepared for forward maximum matching.
class ChinesePhraseTable {
  final Map<String, String> entries;

  /// Longest key, in code points.
  final int maxKeyRunes;

  /// First code point of every key; lets the matcher skip most positions
  /// without building candidate substrings.
  final Set<int> firstRunes;

  const ChinesePhraseTable._(this.entries, this.maxKeyRunes, this.firstRunes);

  static const ChinesePhraseTable empty = ChinesePhraseTable._(
    <String, String>{},
    0,
    <int>{},
  );

  bool get isEmpty => entries.isEmpty;

  /// Parses `key=value|` entries. A bare `key|` entry means "the value is
  /// the [characters] conversion of the key": such phrases change nothing on
  /// their own but still decide where the next match starts, so they are kept.
  factory ChinesePhraseTable.parse(
    String encoded, {
    Map<int, int> characters = const {},
  }) {
    final entries = <String, String>{};
    final firstRunes = <int>{};
    var maxKeyRunes = 0;
    for (final entry in encoded.split('|')) {
      if (entry.isEmpty) continue;
      final separator = entry.indexOf('=');
      if (separator == 0 || separator == entry.length - 1) {
        throw FormatException('Malformed phrase entry: $entry');
      }
      final String key;
      if (separator < 0) {
        key = entry;
        final value = StringBuffer();
        for (final rune in key.runes) {
          value.writeCharCode(characters[rune] ?? rune);
        }
        entries[key] = value.toString();
      } else {
        key = entry.substring(0, separator);
        entries[key] = entry.substring(separator + 1);
      }
      final runes = key.runes;
      firstRunes.add(runes.first);
      if (runes.length > maxKeyRunes) maxKeyRunes = runes.length;
    }
    return ChinesePhraseTable._(
      Map.unmodifiable(entries),
      maxKeyRunes,
      Set.unmodifiable(firstRunes),
    );
  }
}

/// The OpenCC-derived dictionaries, parsed once on first use.
///
/// Parsing the ~50k phrase entries takes some milliseconds; it is deferred
/// until a conversion or comparison actually meets a Han character, so
/// non-Chinese projects never pay for it.
class ChineseScriptTables {
  final Map<int, int> simplifiedToTraditional;
  final Map<int, int> traditionalToSimplified;
  final ChinesePhraseTable simplifiedToTraditionalPhrases;
  final ChinesePhraseTable traditionalToSimplifiedPhrases;
  final Map<int, int> taiwanVariants;
  final ChinesePhraseTable taiwanVariantPhrases;
  final Map<int, int> taiwanVariantsReverse;
  final ChinesePhraseTable taiwanVariantReversePhrases;
  final Map<int, int> hongKongVariants;
  final ChinesePhraseTable hongKongVariantPhrases;
  final Map<int, int> hongKongVariantsReverse;
  final ChinesePhraseTable hongKongVariantReversePhrases;

  /// Characters that only exist in simplified writing (个, 发, 爱 …).
  final Set<int> simplifiedOnly;

  /// Characters that only exist in traditional writing (個, 發, 愛 …).
  final Set<int> traditionalOnly;

  /// Comparison key per code point: regional variants and traditional forms
  /// collapse onto one simplified representative.
  final Map<int, int> comparisonFold;

  final String revision;

  const ChineseScriptTables._({
    required this.simplifiedToTraditional,
    required this.traditionalToSimplified,
    required this.simplifiedToTraditionalPhrases,
    required this.traditionalToSimplifiedPhrases,
    required this.taiwanVariants,
    required this.taiwanVariantPhrases,
    required this.taiwanVariantsReverse,
    required this.taiwanVariantReversePhrases,
    required this.hongKongVariants,
    required this.hongKongVariantPhrases,
    required this.hongKongVariantsReverse,
    required this.hongKongVariantReversePhrases,
    required this.simplifiedOnly,
    required this.traditionalOnly,
    required this.comparisonFold,
    required this.revision,
  });

  static final ChineseScriptTables instance = _build();

  static ChineseScriptTables _build() {
    final simplifiedToTraditional = _parsePairs(
      data.simplifiedToTraditionalCharacters,
    );
    final traditionalToSimplified = _parsePairs(
      data.traditionalToSimplifiedCharacters,
    );
    final taiwanReverse = _parsePairs(data.taiwanVariantReverseCharacters);
    final hongKongReverse = _parsePairs(
      data.hongKongVariantReverseCharacters,
    );
    return ChineseScriptTables._(
      simplifiedToTraditional: simplifiedToTraditional,
      traditionalToSimplified: traditionalToSimplified,
      simplifiedToTraditionalPhrases: ChinesePhraseTable.parse(
        data.simplifiedToTraditionalPhrases,
        characters: simplifiedToTraditional,
      ),
      traditionalToSimplifiedPhrases: ChinesePhraseTable.parse(
        data.traditionalToSimplifiedPhrases,
        characters: traditionalToSimplified,
      ),
      taiwanVariants: _parsePairs(data.taiwanVariantCharacters),
      taiwanVariantPhrases: ChinesePhraseTable.parse(data.taiwanVariantPhrases),
      taiwanVariantsReverse: taiwanReverse,
      taiwanVariantReversePhrases: ChinesePhraseTable.parse(
        data.taiwanVariantReversePhrases,
      ),
      hongKongVariants: _parsePairs(data.hongKongVariantCharacters),
      hongKongVariantPhrases: ChinesePhraseTable.parse(
        data.hongKongVariantPhrases,
      ),
      hongKongVariantsReverse: hongKongReverse,
      hongKongVariantReversePhrases: ChinesePhraseTable.parse(
        data.hongKongVariantReversePhrases,
      ),
      simplifiedOnly: Set.unmodifiable(data.simplifiedOnlyCharacters.runes),
      traditionalOnly: Set.unmodifiable(data.traditionalOnlyCharacters.runes),
      comparisonFold: _buildComparisonFold(
        traditionalToSimplified: traditionalToSimplified,
        reverseVariants: [taiwanReverse, hongKongReverse],
      ),
      revision: data.chineseScriptDataRevision,
    );
  }

  static Map<int, int> _parsePairs(String encoded) {
    final runes = encoded.runes.toList(growable: false);
    if (runes.length.isOdd) {
      throw const FormatException('Character table has an unpaired entry.');
    }
    final table = <int, int>{};
    for (var index = 0; index < runes.length; index += 2) {
      table[runes[index]] = runes[index + 1];
    }
    return Map.unmodifiable(table);
  }

  /// One simplified representative per character.
  ///
  /// Traditional characters take their default simplified form. A regional
  /// variant (裡, 著, 麪) is first mapped back to the standard traditional form,
  /// but only when it is not itself a simplified character: Hong Kong writes
  /// 幺 as 么, and folding the simplified 么 of 什么 that way would stop
  /// 什么 matching 什麼. The simplified step repeats until stable so the fold
  /// is idempotent (薴 → 苧 → 苎).
  static Map<int, int> _buildComparisonFold({
    required Map<int, int> traditionalToSimplified,
    required List<Map<int, int>> reverseVariants,
  }) {
    final simplifiedOutputs = traditionalToSimplified.values.toSet();
    int simplify(int rune) {
      var value = rune;
      for (var guard = 0; guard < 4; guard++) {
        final next = traditionalToSimplified[value];
        if (next == null || next == value) break;
        value = next;
      }
      return value;
    }

    final candidates = <int>{
      ...traditionalToSimplified.keys,
      for (final table in reverseVariants) ...table.keys,
    };
    final fold = <int, int>{};
    for (final rune in candidates) {
      int? standard;
      if (traditionalToSimplified.containsKey(rune)) {
        standard = rune;
      } else if (!simplifiedOutputs.contains(rune)) {
        for (final table in reverseVariants) {
          standard = table[rune];
          if (standard != null) break;
        }
      }
      if (standard == null) continue;
      final value = simplify(standard);
      if (value != rune) fold[rune] = value;
    }
    return Map.unmodifiable(fold);
  }
}
