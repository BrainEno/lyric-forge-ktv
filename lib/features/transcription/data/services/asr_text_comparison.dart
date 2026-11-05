import '../../../lyrics/domain/proofreading/lyric_tokenizer.dart';

/// Normalizes ASR output for line matching and disagreement analysis.
///
/// Tokenization is shared with lyric proofreading so supported writing systems
/// are not silently discarded by the fusion path. Latin diacritics are folded
/// for ASR comparison (for example, "Café" and "Cafe"), while other scripts
/// remain intact.
class AsrTextComparison {
  const AsrTextComparison({this.tokenizer = const LyricTokenizer()});

  final LyricTokenizer tokenizer;

  static const Map<String, String> _latinFoldGroups = {
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
    'b': 'ƀɓƃḃḅḇ',
    'c': 'çćĉċčƈȼḉ',
    'd': 'ďđƌȡḋḍḏḑḓ',
    'e': 'èéêëēĕėęěȅȇẹẻẽếềểễệ',
    'f': 'ƒḟ',
    'g': 'ĝğġģǧǵɠḡ',
    'h': 'ĥħȟḣḥḧḩḫẖ',
    'i': 'ìíîïĩīĭįıǐȉȋịỉ',
    'j': 'ĵǰ',
    'k': 'ķƙǩḱḳḵ',
    'l': 'ĺļľŀłƚḷḹḻḽ',
    'm': 'ḿṁṃ',
    'n': 'ñńņňŉŋǹṅṇṉṋ',
    'o': 'òóôõöøōŏőǒǫǭȍȏơɵọỏốồổỗộớờởỡợ',
    'p': 'ƥṕṗ',
    'r': 'ŕŗřȑȓɍṙṛṝṟ',
    's': 'śŝşšșṡṣṥṧṩẛ',
    't': 'ţťŧțƭȶṫṭṯṱ',
    'u': 'ùúûüũūŭůűųǔǖǘǚǜȕȗụủứừửữự',
    'v': 'ʋṽṿ',
    'w': 'ŵẁẃẅẇẉ',
    'x': 'ẋẍ',
    'y': 'ýÿŷȳẏỳỵỷỹ',
    'z': 'źżžƶẑẓẕ',
  };

  static final Map<int, String> _latinFolds = {
    for (final entry in _latinFoldGroups.entries)
      for (final rune in entry.value.runes) rune: entry.key,
    0x00df: 'ss', // sharp s
    0x00e6: 'ae', // ash
    0x0153: 'oe', // ethel
    0x00fe: 'th', // thorn
  };

  /// Returns a compact, punctuation-insensitive representation for matching.
  String normalize(String text) {
    final tokenized = tokenizer.normalize(text).replaceAll("'", '');
    final output = StringBuffer();
    for (final rune in tokenized.runes) {
      if (rune == 0x20) continue;
      output.write(_latinFolds[rune] ?? String.fromCharCode(rune));
    }
    return output.toString();
  }

  /// Similarity used by the dual-engine disagreement and line-pairing rules.
  /// Empty normalized strings are not evidence that two lines agree.
  double similarity(String left, String right) {
    final a = normalize(left);
    final b = normalize(right);
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final leftRunes = a.runes.toList();
    final rightRunes = b.runes.toList();
    final distance = _levenshtein(leftRunes, rightRunes);
    final longest = leftRunes.length > rightRunes.length
        ? leftRunes.length
        : rightRunes.length;
    return (1.0 - distance / longest).clamp(0.0, 1.0).toDouble();
  }

  /// Detects repeated tokens without dropping non-Latin scripts.
  bool hasSuspiciousRepetition(String text) {
    final normalized = tokenizer.normalize(text).replaceAll("'", '').trim();
    if (normalized.length < 8) return false;

    final tokens = normalized.contains(' ')
        ? normalized.split(' ')
        : normalized.runes.map(String.fromCharCode).toList();
    if (tokens.length < 4) return false;

    var repeated = 0;
    for (var i = 1; i < tokens.length; i++) {
      if (tokens[i] == tokens[i - 1]) repeated++;
    }
    return repeated >= 2 || tokens.toSet().length / tokens.length < 0.45;
  }

  int _levenshtein(List<int> left, List<int> right) {
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < right.length; j++) {
        final substitutionCost = left[i] == right[j] ? 0 : 1;
        final deletion = previous[j + 1] + 1;
        final insertion = current[j] + 1;
        final substitution = previous[j] + substitutionCost;
        var best = deletion < insertion ? deletion : insertion;
        if (substitution < best) best = substitution;
        current[j + 1] = best;
      }
      previous = current;
    }
    return previous[right.length];
  }
}
