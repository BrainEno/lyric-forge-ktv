/// The project's language has no supported ForcedAligner language mapping.
class ForcedAlignmentLanguageResolutionException implements Exception {
  final String language;

  const ForcedAlignmentLanguageResolutionException(this.language);
}

/// Maps a project's free-form lyric language onto the language names the
/// forced aligner accepts.
///
/// Projects store whatever the user typed (`中文`, `Chinese`, `zh-Hant`, …), so
/// the mapping normalizes instead of trusting an enum. An unknown language is
/// an error rather than a silent fallback: aligning Japanese lyrics with the
/// Chinese model produces confident-looking nonsense.
class ForcedAlignmentLanguage {
  const ForcedAlignmentLanguage._();

  static String resolve(String language) {
    final normalized = language.trim().toLowerCase();
    if (normalized.contains('japanese') ||
        normalized.contains('日本') ||
        normalized.contains('日文') ||
        normalized == 'ja' ||
        normalized.startsWith('ja-')) {
      return 'Japanese';
    }
    if (normalized.contains('chinese') ||
        normalized.contains('中文') ||
        normalized.contains('汉语') ||
        normalized == 'zh' ||
        normalized.startsWith('zh-')) {
      return 'Chinese';
    }
    if (normalized.contains('english') ||
        normalized.contains('英文') ||
        normalized == 'en' ||
        normalized.startsWith('en-')) {
      return 'English';
    }
    throw ForcedAlignmentLanguageResolutionException(language);
  }
}
