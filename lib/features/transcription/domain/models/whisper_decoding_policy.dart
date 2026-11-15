import 'dart:convert';

/// Which whisper.cpp decoding profile a run asks for.
///
/// * [standard] is the exact command line every release before the lyric
///   profile used (`-m -f -l -ojf -of -pp`). It is also the safe fallback when
///   a runtime does not advertise a flag the lyric profile wants.
/// * [lyrics] adds only flags verified against the pinned whisper.cpp CLI
///   (`examples/cli/cli.cpp` at 927cfce): a short metadata-only `--prompt` and
///   `--suppress-nst`. See [WhisperDecodingPolicy] for why each one is safe.
enum WhisperDecodingProfile { standard, lyrics }

extension WhisperDecodingProfileId on WhisperDecodingProfile {
  /// Stable identifier written to metadata, diagnostics and the checkpoint
  /// fingerprint. Bump the suffix whenever the emitted arguments change.
  String get id => switch (this) {
    WhisperDecodingProfile.standard => 'whisper-standard-v1',
    WhisperDecodingProfile.lyrics => 'whisper-lyrics-v1',
  };
}

/// Song metadata a recogniser may use as a *decoding hint*.
///
/// This deliberately has no field for lyric text. Reference lyrics are the
/// answer the recogniser is being evaluated against; feeding them to the model
/// would turn every metric into a copy check and contaminate the independent
/// second-engine evidence. Only names that are already visible on the project
/// card (title, artist, album) and terms the user typed for this purpose are
/// accepted.
class RecognitionHints {
  final String songTitle;
  final String artist;
  final String album;

  /// Proper nouns the user explicitly provided (band names, places, invented
  /// words). Never derived from lyrics.
  final List<String> terms;

  const RecognitionHints({
    this.songTitle = '',
    this.artist = '',
    this.album = '',
    this.terms = const <String>[],
  });

  static const RecognitionHints none = RecognitionHints();

  bool get isEmpty =>
      songTitle.trim().isEmpty &&
      artist.trim().isEmpty &&
      album.trim().isEmpty &&
      terms.every((term) => term.trim().isEmpty);
}

/// Flags a concrete whisper-cli binary advertises in its `-h` output.
///
/// whisper.cpp's CLI prints `error: unknown argument` and then exits with code
/// **0** for a flag it does not know, so the exit code cannot be used to learn
/// what a runtime supports. The help text is the only reliable source.
class WhisperRuntimeCapabilities {
  static const String promptFlag = '--prompt';
  static const String suppressNonSpeechFlag = '--suppress-nst';

  /// Long-form flags found in the help text.
  final Set<String> flags;

  /// False when the probe failed or printed nothing recognisable. Callers must
  /// then use [WhisperDecodingProfile.standard] arguments only.
  final bool probed;

  const WhisperRuntimeCapabilities._(this.flags, this.probed);

  static const WhisperRuntimeCapabilities unknown =
      WhisperRuntimeCapabilities._(<String>{}, false);

  factory WhisperRuntimeCapabilities.fromHelpText(String helpText) {
    final flags = <String>{
      for (final match in RegExp(
        r'(?:^|[\s,])(--[a-z][a-z0-9-]*)',
        multiLine: true,
      ).allMatches(helpText))
        match.group(1)!,
    };
    // A real whisper-cli usage text always lists its model and file flags.
    final looksLikeWhisperHelp =
        flags.contains('--model') && flags.contains('--file');
    if (!looksLikeWhisperHelp) return unknown;
    return WhisperRuntimeCapabilities._(Set.unmodifiable(flags), true);
  }

  bool supports(String flag) => probed && flags.contains(flag);

  /// True for the stderr line whisper-cli prints before exiting 0 on a flag it
  /// does not understand.
  static bool isUnknownArgumentLine(String line) =>
      line.toLowerCase().contains('error: unknown argument');
}

/// The concrete arguments one run will pass, plus what diagnostics show.
class WhisperDecodingPlan {
  /// Profile the caller asked for.
  final WhisperDecodingProfile requestedProfile;

  /// Profile the arguments actually implement. Equal to [requestedProfile]
  /// unless the runtime could not support it.
  final WhisperDecodingProfile effectiveProfile;

  /// Arguments appended after the standard `-m -f -l -ojf -of -pp` set.
  final List<String> extraArguments;

  /// The sanitized `--prompt` value, or null when none is sent.
  final String? prompt;

  /// Which hint fields contributed to [prompt] (title, artist, album, terms).
  final List<String> promptSources;

  /// Requested flags the runtime did not advertise and that were therefore
  /// omitted. Empty for a fully supported plan.
  final List<String> omittedFlags;

  const WhisperDecodingPlan({
    required this.requestedProfile,
    required this.effectiveProfile,
    required this.extraArguments,
    required this.prompt,
    required this.promptSources,
    required this.omittedFlags,
  });

  /// The plan that reproduces the pre-profile command line exactly.
  factory WhisperDecodingPlan.standard({
    WhisperDecodingProfile requested = WhisperDecodingProfile.standard,
    List<String> omittedFlags = const <String>[],
  }) => WhisperDecodingPlan(
    requestedProfile: requested,
    effectiveProfile: WhisperDecodingProfile.standard,
    extraArguments: const <String>[],
    prompt: null,
    promptSources: const <String>[],
    omittedFlags: List.unmodifiable(omittedFlags),
  );

  bool get isStandard => extraArguments.isEmpty;

  /// Diagnostics/metadata shape. Holds no audio or lyric content: the prompt is
  /// built only from project metadata the user already sees.
  Map<String, dynamic> toMetadata({String? fallbackReason}) => {
    'requestedProfile': requestedProfile.id,
    'effectiveProfile': effectiveProfile.id,
    'arguments': [
      for (var index = 0; index < extraArguments.length; index++)
        // The prompt value is reported separately and only by length.
        if (index > 0 && extraArguments[index - 1] == '--prompt')
          '<prompt>'
        else
          extraArguments[index],
    ],
    'promptSources': promptSources,
    'promptRunes': prompt?.runes.length ?? 0,
    'promptUtf8Bytes': prompt == null ? 0 : utf8.encode(prompt!).length,
    if (omittedFlags.isNotEmpty) 'omittedFlags': omittedFlags,
    'fallbackReason': ?fallbackReason,
  };
}

/// Builds a lyric-aware but conservative whisper.cpp decoding plan.
///
/// Why only these flags (verified in `examples/cli/cli.cpp` and
/// `src/whisper.cpp` at the pinned revision 927cfce):
///
/// * `--prompt` seeds the rolling text context of the *first* window only. It
///   is limited by the library to `n_text_ctx / 2` (224) tokens. The prompt is
///   capped at [maxPromptUtf8Bytes] UTF-8 bytes; a byte-level BPE token always
///   covers at least one byte, so the token count can never exceed the budget.
///   `--carry-initial-prompt` is never used: it re-prepends the prompt to every
///   window, which biases long songs towards the prompt words.
/// * `--suppress-nst` suppresses non-speech tokens (♪, bracketed sound
///   descriptions) that whisper emits over instrumental passages; those rows
///   are never lyrics and only add review work.
///
/// Flags deliberately not used: `--vad` needs a separate VAD model file that
/// the managed runtime does not ship; beam size/best-of already default to 5
/// in the library, and temperature fallback is already on by default, so
/// re-stating them would change nothing but the fingerprint; `-mc 0` would
/// disable the prompt entirely (the prompt only applies when
/// `n_max_text_ctx > 0`).
class WhisperDecodingPolicy {
  static const int maxPromptUtf8Bytes = 200;
  static const int maxFieldRunes = 64;
  static const int maxTermRunes = 32;
  static const int maxTerms = 12;

  const WhisperDecodingPolicy();

  WhisperDecodingPlan plan({
    required WhisperDecodingProfile profile,
    required RecognitionHints hints,
    required String language,
    required WhisperRuntimeCapabilities capabilities,
  }) {
    if (profile == WhisperDecodingProfile.standard) {
      return WhisperDecodingPlan.standard();
    }

    final omitted = <String>[];
    final extra = <String>[];
    final promptResult = buildPrompt(hints: hints, language: language);
    String? prompt;
    if (promptResult != null) {
      if (capabilities.supports(WhisperRuntimeCapabilities.promptFlag)) {
        prompt = promptResult.text;
        extra.addAll([WhisperRuntimeCapabilities.promptFlag, prompt]);
      } else {
        omitted.add(WhisperRuntimeCapabilities.promptFlag);
      }
    }
    if (capabilities.supports(
      WhisperRuntimeCapabilities.suppressNonSpeechFlag,
    )) {
      extra.add(WhisperRuntimeCapabilities.suppressNonSpeechFlag);
    } else {
      omitted.add(WhisperRuntimeCapabilities.suppressNonSpeechFlag);
    }

    if (extra.isEmpty) {
      return WhisperDecodingPlan.standard(
        requested: profile,
        omittedFlags: omitted,
      );
    }
    return WhisperDecodingPlan(
      requestedProfile: profile,
      effectiveProfile: profile,
      extraArguments: List.unmodifiable(extra),
      prompt: prompt,
      promptSources: prompt == null
          ? const <String>[]
          : List.unmodifiable(promptResult!.sources),
      omittedFlags: List.unmodifiable(omitted),
    );
  }

  /// Deterministic material for the checkpoint fingerprint: anything that can
  /// change Whisper's output for the same audio. Capability detection is not
  /// included because the executable path already is.
  String fingerprintMaterial({
    required WhisperDecodingProfile profile,
    required RecognitionHints hints,
    required String language,
  }) {
    if (profile == WhisperDecodingProfile.standard) return profile.id;
    final prompt = buildPrompt(hints: hints, language: language)?.text ?? '';
    return '${profile.id}\u0001$prompt';
  }

  /// Builds the language-adapted prompt, or null when no usable hint exists.
  WhisperPrompt? buildPrompt({
    required RecognitionHints hints,
    required String language,
  }) {
    final title = sanitizeTitle(hints.songTitle);
    final artist = sanitizeField(hints.artist);
    final album = sanitizeField(hints.album);
    final terms = <String>[];
    final seen = <String>{};
    for (final raw in hints.terms) {
      if (terms.length >= maxTerms) break;
      final term = _truncateRunes(sanitizeField(raw), maxTermRunes);
      if (term.isEmpty || !seen.add(term.toLowerCase())) continue;
      terms.add(term);
    }
    if (title.isEmpty && artist.isEmpty && terms.isEmpty) return null;

    final template = _PromptTemplate.forLanguage(language);
    final sources = <String>[];
    final parts = <String>[];
    if (title.isNotEmpty) {
      parts.add(template.title(title));
      sources.add('title');
    }
    if (artist.isNotEmpty) {
      parts.add(template.artist(artist));
      sources.add('artist');
    }
    // The album is the weakest hint; it only fits when the budget allows.
    if (album.isNotEmpty && album != title) {
      final candidate = template.join([...parts, template.album(album)]);
      if (utf8.encode(candidate).length <= maxPromptUtf8Bytes) {
        parts.add(template.album(album));
        sources.add('album');
      }
    }

    var text = template.join(parts);
    if (terms.isNotEmpty) {
      // Drop whole terms from the end instead of cutting one in half.
      for (var count = terms.length; count > 0; count--) {
        final withTerms = template.join([
          ...parts,
          template.terms(terms.take(count).toList()),
        ]);
        if (utf8.encode(withTerms).length <= maxPromptUtf8Bytes) {
          text = withTerms;
          sources.add('terms');
          break;
        }
      }
    }
    text = _truncateUtf8(text, maxPromptUtf8Bytes);
    if (text.trim().isEmpty) return null;
    return WhisperPrompt(text: text, sources: List.unmodifiable(sources));
  }

  /// Removes control characters, collapses whitespace and caps the length.
  static String sanitizeField(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029]'), ' ')
        // Quote-like and bracket characters invite the decoder to emit them.
        .replaceAll(RegExp(r'["“”«»<>{}\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _truncateRunes(cleaned, maxFieldRunes);
  }

  /// Project names are frequently file names: strip the extension, a leading
  /// track number and bracketed release noise such as "(Official Video)".
  static String sanitizeTitle(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(
        r'\.(mp3|flac|wav|m4a|aac|ogg|opus|wma|ape|alac|mp4|mkv|webm)$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._)]\s*'), '');
    value = value.replaceAll(
      RegExp(
        r'[\(\[（【][^\)\]）】]*(official|video|audio|lyric|lyrics|mv|hd|4k|'
        r'karaoke|instrumental|remaster|伴奏|歌词|歌詞|官方|高清|卡拉)'
        r'[^\)\]）】]*[\)\]）】]',
        caseSensitive: false,
      ),
      ' ',
    );
    value = value.replaceAll('_', ' ');
    return sanitizeField(value);
  }

  static String _truncateRunes(String value, int maxRunes) {
    final runes = value.runes.toList();
    if (runes.length <= maxRunes) return value;
    return _dropDanglingJoiners(String.fromCharCodes(runes.take(maxRunes)));
  }

  /// Truncates on whole code points so no surrogate pair or UTF-8 sequence is
  /// ever split, then removes joiners left dangling at the cut.
  static String _truncateUtf8(String value, int maxBytes) {
    if (utf8.encode(value).length <= maxBytes) return value;
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in value.runes) {
      final width = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + width > maxBytes) break;
      buffer.writeCharCode(rune);
      bytes += width;
    }
    return _dropDanglingJoiners(buffer.toString()).trimRight();
  }

  static String _dropDanglingJoiners(String value) {
    var runes = value.runes.toList();
    bool isJoiner(int rune) =>
        rune == 0x200D || // ZERO WIDTH JOINER
        (rune >= 0xFE00 && rune <= 0xFE0F) || // variation selectors
        (rune >= 0x0300 && rune <= 0x036F); // combining diacritics
    while (runes.isNotEmpty && isJoiner(runes.last)) {
      runes = runes.sublist(0, runes.length - 1);
    }
    return String.fromCharCodes(runes).trim();
  }
}

class WhisperPrompt {
  final String text;
  final List<String> sources;

  const WhisperPrompt({required this.text, required this.sources});
}

/// Short, natural phrasing per language. Whisper treats the prompt as the
/// preceding transcript, so it is written in the script the lyrics use and
/// without the words "transcribe" or "lyrics follow", which the model tends to
/// echo over silent intros.
class _PromptTemplate {
  final String Function(String) title;
  final String Function(String) artist;
  final String Function(String) album;
  final String Function(List<String>) terms;
  final String separator;
  final String terminator;

  const _PromptTemplate({
    required this.title,
    required this.artist,
    required this.album,
    required this.terms,
    required this.separator,
    required this.terminator,
  });

  String join(List<String> parts) =>
      parts.isEmpty ? '' : '${parts.join(separator)}$terminator';

  static _PromptTemplate forLanguage(String language) {
    final code = language.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    return switch (code) {
      'zh' || 'yue' => _PromptTemplate(
        title: (value) => '歌曲《$value》',
        artist: (value) => '演唱：$value',
        album: (value) => '专辑：$value',
        terms: (values) => '人名与专有名词：${values.join('、')}',
        separator: '，',
        terminator: '。',
      ),
      'ja' => _PromptTemplate(
        title: (value) => '曲名「$value」',
        artist: (value) => '歌手：$value',
        album: (value) => 'アルバム：$value',
        terms: (values) => '固有名詞：${values.join('、')}',
        separator: '、',
        terminator: '。',
      ),
      'en' => _PromptTemplate(
        title: (value) => 'Song: $value',
        artist: (value) => 'Artist: $value',
        album: (value) => 'Album: $value',
        terms: (values) => 'Names: ${values.join(', ')}',
        separator: '. ',
        terminator: '.',
      ),
      // With automatic language detection an English or Chinese template could
      // nudge the decoder towards that language, so only the bare names are
      // given, in whatever script the user typed them.
      _ => _PromptTemplate(
        title: (value) => value,
        artist: (value) => value,
        album: (value) => value,
        terms: (values) => values.join(', '),
        separator: ', ',
        terminator: '',
      ),
    };
  }
}
