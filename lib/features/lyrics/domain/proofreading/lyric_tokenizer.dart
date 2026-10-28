class LyricTokenizer {
  const LyricTokenizer();

  String normalize(String input) => tokenize(input).join(' ');

  List<String> tokenize(String input) {
    final runes = input.toLowerCase().runes.map(_normalizeRune).toList();
    final tokens = <String>[];
    final current = StringBuffer();
    void flush() {
      if (current.length == 0) return;
      tokens.add(current.toString());
      current.clear();
    }

    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (_isCjkRune(rune)) {
        flush();
        tokens.add(String.fromCharCode(rune));
      } else if (_isWordRune(rune)) {
        current.writeCharCode(rune);
      } else if (rune == 0x27 &&
          current.length > 0 &&
          i + 1 < runes.length &&
          _isWordRune(runes[i + 1])) {
        current.writeCharCode(0x27);
      } else {
        flush();
      }
    }
    flush();
    return tokens;
  }

  bool isCjkToken(String token) {
    final runes = token.runes;
    return runes.length == 1 && _isCjkRune(runes.first);
  }

  int _normalizeRune(int rune) {
    if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
    if (rune == 0x3000) return 0x20;
    if (rune == 0x2019 ||
        rune == 0x2018 ||
        rune == 0x02bc ||
        rune == 0x0060 ||
        rune == 0x00b4) {
      return 0x27;
    }
    return rune;
  }

  bool _isWordRune(int rune) =>
      (rune >= 0x61 && rune <= 0x7a) ||
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x00c0 && rune <= 0x024f && rune != 0x00d7 && rune != 0x00f7) ||
      (rune >= 0x0370 && rune <= 0x03ff) ||
      (rune >= 0x0400 && rune <= 0x04ff);

  bool _isCjkRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0x3040 && rune <= 0x30ff) ||
      (rune >= 0xac00 && rune <= 0xd7af);
}
