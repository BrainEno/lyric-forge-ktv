import 'dart:math' as math;

import 'transcription_models.dart';
import 'vocal_activity.dart';
import 'whisper_decoding_policy.dart';

/// One stretch of the song the language probe listens to (D-061).
class SpokenLanguageWindow {
  final Duration start;
  final Duration end;

  const SpokenLanguageWindow(this.start, this.end);

  Duration get duration => end - start;

  Map<String, Object?> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };
}

/// What Whisper's language identification said about one probe clip.
class SpokenLanguageProbe {
  /// Whisper language code, e.g. `en`, `zh`, `nn`.
  final String language;

  /// Whisper's probability for [language], 0 to 1.
  final double probability;

  const SpokenLanguageProbe(this.language, this.probability);

  Map<String, Object?> toJson() => {
    'language': language,
    'probability': double.parse(probability.toStringAsFixed(3)),
  };
}

/// Where the language a run recognises in came from.
enum SpokenLanguageSource {
  /// The user chose a language in the recognition settings.
  configured,

  /// Whisper's language identification on the sung parts of the song.
  detected,

  /// The script or words of the song title and artist.
  songInfo,

  /// Nothing usable: the engines detect on their own, as before D-061.
  unresolved,
}

/// The language a recognition run uses, and how it was found (D-061).
///
/// Stored in the draft's metadata under [metadataKey] so later steps (gap
/// filling, re-recognising a span in the editor) reuse it instead of letting
/// Whisper guess again from a few seconds of audio.
class SpokenLanguageResolution {
  static const String metadataKey = 'spokenLanguage';

  /// A Whisper language code, or `auto` when [source] is
  /// [SpokenLanguageSource.unresolved].
  final String language;
  final SpokenLanguageSource source;
  final List<SpokenLanguageProbe> probes;
  final List<SpokenLanguageWindow> windows;

  /// What the song title and artist suggest, when anything.
  final String? songInfoLanguage;

  /// Why probing failed, for diagnostics; the run continues regardless.
  final String? error;

  const SpokenLanguageResolution({
    required this.language,
    required this.source,
    this.probes = const [],
    this.windows = const [],
    this.songInfoLanguage,
    this.error,
  });

  const SpokenLanguageResolution.unresolved({
    this.probes = const [],
    this.windows = const [],
    this.songInfoLanguage,
    this.error,
  }) : language = SpokenLanguagePolicy.auto,
       source = SpokenLanguageSource.unresolved;

  bool get isResolved => source != SpokenLanguageSource.unresolved;

  /// One line for the progress display.
  String get summary => switch (source) {
    SpokenLanguageSource.configured =>
      '识别语言：${SpokenLanguagePolicy.label(language)}（识别设置）',
    SpokenLanguageSource.detected =>
      '演唱语言：${SpokenLanguagePolicy.label(language)}',
    SpokenLanguageSource.songInfo =>
      '演唱语言：${SpokenLanguagePolicy.label(language)}（按歌名判断）',
    SpokenLanguageSource.unresolved => '没能判断演唱语言，交给识别引擎自动检测',
  };

  Map<String, Object?> toJson() => {
    'language': language,
    'source': source.name,
    'probes': [for (final probe in probes) probe.toJson()],
    'windows': [for (final window in windows) window.toJson()],
    'songInfoLanguage': ?songInfoLanguage,
    'error': ?error,
  };

  /// The language a stored resolution settled on, or null when there is
  /// none or it was left to the engines.
  static String? resolvedLanguageOf(Map<String, dynamic> metadata) {
    final raw = metadata[metadataKey];
    if (raw is! Map) return null;
    if (raw['source'] == SpokenLanguageSource.unresolved.name) return null;
    return SpokenLanguagePolicy.languageCode(raw['language']?.toString());
  }

  /// The language a project's last recognition was sung in, for steps that
  /// recognise a few seconds of it again: the stored resolution, else the
  /// language the engines reported for the whole song when it is
  /// [SpokenLanguagePolicy.usableLanguage]. Null when neither says.
  static String? languageOfProject(Map<String, dynamic> projectMetadata) {
    final transcription = projectMetadata['transcription'];
    if (transcription is! Map) return null;
    final stored = resolvedLanguageOf(Map<String, dynamic>.from(transcription));
    if (stored != null) return stored;
    return SpokenLanguagePolicy.usableLanguage(
      transcription['detectedLanguage']?.toString(),
    );
  }
}

/// Decides which language a song is recognised in when the settings say
/// 自动检测 (D-061).
///
/// whisper.cpp identifies the language from the first 30 seconds of its
/// input and nothing else (`whisper_full_with_state` detects at offset 0,
/// whatever `--offset-t` says). A song that opens with an instrumental, or a
/// separated vocal stem that is silent until the first verse, gives it
/// nothing to listen to. On music and silence Whisper typically answers with
/// a language nobody sings in (Norwegian Nynorsk `nn` is the classic), then
/// decodes the whole song in that language and returns a word or two.
///
/// The probe therefore listens where the singing is: the [window]-long
/// stretches with the most voice, up to [windowsPerProbe] of them joined
/// into one 30-second clip, the exact span Whisper's detector reads.
class SpokenLanguagePolicy {
  const SpokenLanguagePolicy({
    this.window = const Duration(seconds: 10),
    this.windowsPerProbe = 3,
    this.maxProbes = 2,
    this.minimumVoiced = const Duration(seconds: 3),
  });

  final Duration window;
  final int windowsPerProbe;
  final int maxProbes;

  /// A window counts only with at least this much singing in it (when the
  /// input is a clean vocal stem whose singing can be told apart).
  final Duration minimumVoiced;

  static const String auto = 'auto';

  /// Mean RMS (about -60 dBFS) under which a stretch of a mix is silence.
  static const double silenceRms = 0.001;

  /// A probe below this probability does not decide the language alone.
  static const double minimumProbability = 0.5;

  /// The languages in [hallucinationProne] need this much.
  static const double hallucinationProbability = 0.9;

  /// When no probe is reliable and the song info says nothing, the best
  /// probe is still used from this probability on: it heard singing, which
  /// is more than whisper's own look at the intro does.
  static const double fallbackProbability = 0.25;

  /// Languages Whisper reports for silence, applause and instruments far
  /// more often than anybody sings in them. They are accepted only with a
  /// very high probability.
  static final Set<String> hallucinationProne = Set.unmodifiable(
    ('nn no cy la haw mi jw su sn yo ln ha ba tt tk br oc bo sa fo ht lb '
            'mt my lo sd am mg as tl ps yi sw')
        .split(' '),
  );

  static bool isAuto(String language) {
    final value = language.trim().toLowerCase();
    return value.isEmpty || value == auto;
  }

  /// [language] normalised when it is a plain language code (not `auto`,
  /// not `unknown`), otherwise null.
  static String? languageCode(String? language) {
    final value = language?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(value) || value == auto) return null;
    return value;
  }

  /// [language] when it can be trusted without a confident probe: a
  /// [languageCode] that is not one of [hallucinationProne].
  static String? usableLanguage(String? language) {
    final value = languageCode(language);
    if (value == null || hallucinationProne.contains(value)) return null;
    return value;
  }

  /// [config] pinned to [language] when the settings say 自动检测 and
  /// [language] is a [languageCode]; otherwise [config] unchanged.
  static TranscriptionConfig withKnownLanguage(
    TranscriptionConfig config,
    String? language,
  ) {
    if (!isAuto(config.language)) return config;
    final known = languageCode(language);
    return known == null ? config : config.copyWith(language: known);
  }

  /// Chinese name of a language code, for messages.
  static String label(String language) => switch (language) {
    'zh' => '中文',
    'yue' => '粤语',
    'en' => '英文',
    'ja' => '日文',
    'ko' => '韩文',
    'fr' => '法语',
    'de' => '德语',
    'es' => '西班牙语',
    'pt' => '葡萄牙语',
    'it' => '意大利语',
    'ru' => '俄语',
    'th' => '泰语',
    'vi' => '越南语',
    'id' => '印尼语',
    'ms' => '马来语',
    'nl' => '荷兰语',
    'sv' => '瑞典语',
    'tr' => '土耳其语',
    'hi' => '印地语',
    'ar' => '阿拉伯语',
    'nn' || 'no' => '挪威语',
    _ => language,
  };

  /// The stretches each probe listens to: per probe up to [windowsPerProbe]
  /// windows in timeline order, the most sung ones in the first probe.
  /// Empty when there is nothing that sounds like singing.
  List<List<SpokenLanguageWindow>> probeWindows(
    VocalEnergyEnvelope envelope,
    VocalActivityProfile profile,
  ) {
    final duration = envelope.duration;
    if (duration <= Duration.zero || envelope.frameRms.isEmpty) return const [];
    final total = window * windowsPerProbe;
    if (duration <= total) {
      if (profile.isReliable && profile.voiced < minimumVoiced) return const [];
      return [
        [SpokenLanguageWindow(Duration.zero, duration)],
      ];
    }

    final count = duration.inMicroseconds ~/ window.inMicroseconds;
    final scored = <({int index, double score})>[];
    for (var index = 0; index < count; index++) {
      final start = window * index;
      final end = start + window;
      final double score;
      if (profile.isReliable) {
        // A clean vocal stem: how much singing the window holds.
        final voiced = profile.voicedWithin(start, end);
        if (voiced < minimumVoiced) continue;
        score = voiced.inMilliseconds.toDouble();
      } else {
        // A mix: loudness, which in a song mostly means the sung parts.
        score = _meanRms(envelope, start, end);
      }
      scored.add((index: index, score: score));
    }
    if (scored.isEmpty) return const [];
    if (!profile.isReliable) {
      // Leave out near-silent stretches of a mix (fade-ins, gaps), and
      // everything when all of it is near digital silence.
      final loudest = scored.map((entry) => entry.score).reduce(math.max);
      final floor = math.max(loudest * 0.2, silenceRms);
      scored.removeWhere((entry) => entry.score < floor);
      if (scored.isEmpty) return const [];
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });

    final probes = <List<SpokenLanguageWindow>>[];
    for (
      var offset = 0;
      offset < scored.length && probes.length < maxProbes;
      offset += windowsPerProbe
    ) {
      final picked =
          scored.skip(offset).take(windowsPerProbe).toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      probes.add([
        for (final entry in picked)
          SpokenLanguageWindow(
            window * entry.index,
            window * (entry.index + 1),
          ),
      ]);
    }
    return probes;
  }

  /// Whether [probe] decides the language on its own.
  bool isReliable(SpokenLanguageProbe probe) {
    if (languageCode(probe.language) == null) return false;
    final needed = hallucinationProne.contains(probe.language)
        ? hallucinationProbability
        : minimumProbability;
    return probe.probability >= needed;
  }

  /// The language the run uses. In order: a reliable probe (the most
  /// confident one), the song info, the best ordinary probe from
  /// [fallbackProbability], otherwise left to the engines.
  SpokenLanguageResolution decide({
    required List<SpokenLanguageProbe> probes,
    String? songInfoLanguage,
    List<SpokenLanguageWindow> windows = const [],
    String? error,
  }) {
    final ranked = [...probes]
      ..sort((a, b) => b.probability.compareTo(a.probability));
    SpokenLanguageResolution resolved(
      String language,
      SpokenLanguageSource source,
    ) => SpokenLanguageResolution(
      language: language,
      source: source,
      probes: List.unmodifiable(probes),
      windows: List.unmodifiable(windows),
      songInfoLanguage: songInfoLanguage,
      error: error,
    );

    for (final probe in ranked) {
      if (isReliable(probe)) {
        return resolved(probe.language, SpokenLanguageSource.detected);
      }
    }
    final hint = usableLanguage(songInfoLanguage);
    if (hint != null) return resolved(hint, SpokenLanguageSource.songInfo);
    for (final probe in ranked) {
      final language = usableLanguage(probe.language);
      if (language != null && probe.probability >= fallbackProbability) {
        return resolved(language, SpokenLanguageSource.detected);
      }
    }
    return SpokenLanguageResolution.unresolved(
      probes: List.unmodifiable(probes),
      windows: List.unmodifiable(windows),
      songInfoLanguage: songInfoLanguage,
      error: error,
    );
  }

  /// What the song title, artist and album suggest: `ko`, `ja` or `zh` from
  /// their script, `en` from common English words. Null when they say
  /// nothing (empty, or Latin text without English words).
  static String? languageFromSongInfo(RecognitionHints hints) {
    final text = [
      WhisperDecodingPolicy.sanitizeTitle(hints.songTitle),
      hints.artist,
      hints.album,
    ].join(' ');
    if (text.trim().isEmpty) return null;
    if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]').hasMatch(text)) {
      return 'ko';
    }
    if (RegExp(r'[\u3040-\u30FF\u31F0-\u31FF]').hasMatch(text)) return 'ja';
    if (RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]').hasMatch(text)) return 'zh';
    // Letters other languages write and English does not.
    if (RegExp(r'[À-ÖØ-öø-ÿĀ-žА-я]').hasMatch(text)) return null;
    final words = RegExp(
      r"[a-z]+(?:'[a-z]+)?",
    ).allMatches(text.toLowerCase()).map((match) => match.group(0)!).toList();
    if (words.isEmpty) return null;
    final english = words.where(_englishWords.contains).length;
    // At least a quarter of the words, so one loan word decides nothing.
    return english > 0 && english * 4 >= words.length ? 'en' : null;
  }

  /// Function words and song-title staples that are English and not also
  /// common words of another language written in Latin letters.
  static final Set<String> _englishWords = Set.unmodifiable(
    ("the and of you your my with this that is are be it it's i'm don't "
            "can't won't to for all we they what when where love night baby "
            'heart time people light fire rain storm world girl boy man woman '
            'dream blue road home life day end break through side other riders '
            'doors beatles stones eagles just like never forever again back '
            'down up over into out without tonight yesterday tomorrow')
        .split(' '),
  );

  static double _meanRms(
    VocalEnergyEnvelope envelope,
    Duration start,
    Duration end,
  ) {
    final frame = envelope.frameLength.inMicroseconds;
    if (frame <= 0) return 0;
    final from = (start.inMicroseconds ~/ frame).clamp(
      0,
      envelope.frameRms.length,
    );
    final to = (end.inMicroseconds ~/ frame).clamp(
      from,
      envelope.frameRms.length,
    );
    if (to <= from) return 0;
    var sum = 0.0;
    for (var index = from; index < to; index++) {
      sum += envelope.frameRms[index];
    }
    return sum / (to - from);
  }
}
