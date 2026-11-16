/// Removes secrets and personal identifiers from diagnostic text.
///
/// Every string that reaches a log sink or the diagnostics report passes
/// through here, so the "never log tokens" rule no longer depends on each call
/// site remembering it. The rules are deliberately conservative: they replace
/// the *value* and keep the key, so a report still shows that a token was
/// present without revealing it.
///
/// What is removed:
/// - values of secret-looking keys in URLs, headers, JSON and `key=value`
///   text (`token`, `password`, `api_key`, `authorization`, `KTV-QUERY-TOKEN` …);
/// - `Bearer`/`Basic` credentials and `user:password@` URL user info;
/// - e-mail addresses;
/// - the user name inside home-directory paths (`/Users/alice/…` → `~/…`).
///
/// Lyrics and audio are not detectable as such; callers must log metadata
/// (counts, durations, states), never lyric text. The report builder only
/// accepts structured sections for the same reason.
class LogRedactor {
  /// Absolute home directories of the current user (from `HOME` or
  /// `USERPROFILE`); replaced by `~` wherever they occur.
  final List<String> homeDirectories;

  LogRedactor({Iterable<String> homeDirectories = const []})
    : homeDirectories = [
        for (final home in homeDirectories)
          if (_usableHome(home)) _trimSeparator(home),
      ]..sort((a, b) => b.length.compareTo(a.length));

  static const String redacted = '<redacted>';

  static const String _secretKeys =
      r'(?:access[_-]?token|refresh[_-]?token|id[_-]?token|auth[_-]?token|'
      r'ktv[_-]?query[_-]?token|session[_-]?token|token|api[_-]?key|apikey|'
      r'secret|client[_-]?secret|password|passwd|pwd|pairing[_-]?code|pin|'
      r'signature|sig|authorization|cookie|set-cookie)';

  /// `"token": "value"` and `'token': 'value'`.
  static final RegExp _quotedPair = RegExp(
    '(["\'])($_secretKeys)\\1(\\s*:\\s*)(["\'])([^"\']*)\\4',
    caseSensitive: false,
  );

  /// `Authorization: Bearer abc`, `KTV-QUERY-TOKEN: abc`, `token=abc`,
  /// `?token=abc&x=1`. The key must not be the tail of a longer word, so
  /// `fingerprint=` or `tokenizer=` stay intact.
  static final RegExp _keyValue = RegExp(
    '(?<![A-Za-z0-9_-])($_secretKeys)(\\s*[:=]\\s*)'
    r'(?:(bearer|basic)\s+)?'
    // Never take the scheme word itself as the value: on a second pass
    // `Bearer <redacted>` must stay as it is.
    r'(?!(?:bearer|basic)\s)'
    r'([^\s&,;"'
    "'"
    r'<>)\]}]+)',
    caseSensitive: false,
  );

  /// A lone `Bearer xyz` without a key in front of it.
  static final RegExp _bearer = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );

  /// `scheme://user:password@host`.
  static final RegExp _userInfo = RegExp(
    r'([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@',
    caseSensitive: false,
  );

  static final RegExp _email = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );

  /// Home directories of any user, for paths copied from another machine or
  /// produced before [homeDirectories] was known.
  static final RegExp _genericHome = RegExp(
    r'(?<![\w.-])(?:/Users/|/home/|[A-Za-z]:\\Users\\|[A-Za-z]:/Users/)'
    r'(?!Shared[\\/]|Public[\\/]|Default[\\/])'
    r'[^\\/\s]+',
  );

  String redact(String input) {
    if (input.isEmpty) return input;
    var text = input;
    for (final home in homeDirectories) {
      text = _replaceHome(text, home);
    }
    text = text.replaceAllMapped(_genericHome, (_) => '~');
    text = text.replaceAllMapped(_userInfo, (match) => '${match[1]}$redacted@');
    text = text.replaceAllMapped(
      _quotedPair,
      (match) =>
          '${match[1]}${match[2]}${match[1]}${match[3]}${match[4]}'
          '$redacted${match[4]}',
    );
    text = text.replaceAllMapped(_keyValue, (match) {
      if (match[4] == redacted) return match[0]!;
      final scheme = match[3] == null ? '' : '${match[3]} ';
      return '${match[1]}${match[2]}$scheme$redacted';
    });
    text = text.replaceAllMapped(_bearer, (match) => '${match[1]} $redacted');
    text = text.replaceAll(_email, '<email>');
    return text;
  }

  /// Redacts every string inside a JSON-like value (maps, lists, scalars).
  Object? redactValue(Object? value) {
    if (value is String) return redact(value);
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _isSecretKey('${entry.key}')
              ? (entry.value == null ? null : redacted)
              : redactValue(entry.value),
      };
    }
    if (value is Iterable) return [for (final item in value) redactValue(item)];
    return value;
  }

  static final RegExp _secretKeyOnly = RegExp(
    '^$_secretKeys\$',
    caseSensitive: false,
  );

  static bool _isSecretKey(String key) => _secretKeyOnly.hasMatch(key.trim());

  static String _replaceHome(String text, String home) {
    // Windows paths are case-insensitive and may use either separator.
    final windows = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(home);
    if (!windows) return text.replaceAll(home, '~');
    final source = StringBuffer();
    for (final char in home.split('')) {
      source.write(
        char == '/' || char == r'\' ? r'[\\/]' : RegExp.escape(char),
      );
    }
    final pattern = RegExp(source.toString(), caseSensitive: false);
    return text.replaceAll(pattern, '~');
  }

  static bool _usableHome(String home) {
    final trimmed = _trimSeparator(home.trim());
    // A root or drive-only "home" would erase every path in the report.
    return trimmed.length > 3 && trimmed != '/root';
  }

  static String _trimSeparator(String path) {
    var value = path.trim();
    while (value.length > 1 && (value.endsWith('/') || value.endsWith(r'\'))) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
