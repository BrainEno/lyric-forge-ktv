import '../text/chinese_script_converter.dart';

/// How recognition drafts should treat simplified and traditional Chinese.
enum ChineseScriptPreference {
  /// Unify the lines written in the minority script to the script most lines
  /// already use; a document that is already consistent is left untouched.
  auto,

  /// Never convert; script differences are still ignored when comparing.
  keep,
  simplified,
  traditionalTaiwan,
  traditionalHongKong;

  /// The explicit output script, or null for [auto] and [keep].
  ChineseScriptTarget? get explicitTarget => switch (this) {
    ChineseScriptPreference.simplified => ChineseScriptTarget.simplified,
    ChineseScriptPreference.traditionalTaiwan =>
      ChineseScriptTarget.traditionalTaiwan,
    ChineseScriptPreference.traditionalHongKong =>
      ChineseScriptTarget.traditionalHongKong,
    ChineseScriptPreference.auto || ChineseScriptPreference.keep => null,
  };

  static ChineseScriptPreference fromName(Object? name) =>
      ChineseScriptPreference.values.asNameMap()[name] ??
      ChineseScriptPreference.auto;

  static ChineseScriptPreference forTarget(ChineseScriptTarget target) =>
      switch (target) {
        ChineseScriptTarget.simplified => ChineseScriptPreference.simplified,
        ChineseScriptTarget.traditionalTaiwan =>
          ChineseScriptPreference.traditionalTaiwan,
        ChineseScriptTarget.traditionalHongKong =>
          ChineseScriptPreference.traditionalHongKong,
      };
}

/// Interprets the language tags the app stores (`zh`, `zh-TW`, `zh-Hant`,
/// `yue`, `auto` …) for script decisions.
class ChineseLanguageTag {
  const ChineseLanguageTag._();

  static List<String> _parts(String? tag) => (tag ?? '')
      .trim()
      .toLowerCase()
      .split(RegExp(r'[-_]'))
      .where((part) => part.isNotEmpty)
      .toList();

  /// True when the tag names a Chinese language; null when it names none
  /// (`auto`, empty) and the text itself has to decide.
  static bool? isChinese(String? tag) {
    final parts = _parts(tag);
    if (parts.isEmpty || parts.first == 'auto' || parts.first == 'und') {
      return null;
    }
    return const {
      'zh',
      'zho',
      'chi',
      'cmn',
      'yue',
      'wuu',
      'nan',
      'hak',
      'gan',
      'hsn',
    }.contains(parts.first);
  }

  /// The script a tag implies, if it implies one (`zh-TW`, `zh-Hans`, `yue`).
  static ChineseScriptTarget? impliedTarget(String? tag) {
    final parts = _parts(tag);
    if (parts.isEmpty || isChinese(tag) != true) return null;
    if (parts.contains('hans') ||
        parts.contains('cn') ||
        parts.contains('sg') ||
        parts.contains('my')) {
      return ChineseScriptTarget.simplified;
    }
    if (parts.contains('hk') || parts.contains('mo')) {
      return ChineseScriptTarget.traditionalHongKong;
    }
    if (parts.contains('tw') || parts.contains('hant')) {
      return ChineseScriptTarget.traditionalTaiwan;
    }
    return null;
  }

  /// Cantonese lyrics are conventionally written with Hong Kong forms.
  static bool isCantonese(String? tag) {
    final parts = _parts(tag);
    return parts.isNotEmpty && parts.first == 'yue';
  }
}
