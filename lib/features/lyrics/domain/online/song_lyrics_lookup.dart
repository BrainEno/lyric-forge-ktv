import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../services/lyric_file_import_service.dart';
import '../text/chinese_script_converter.dart';
import 'online_lyric_candidate.dart';
import 'online_lyric_query.dart';
import 'online_lyric_sanitizer.dart';

/// `lyricSource` written on a project whose lyrics came from a lyric site.
const String onlineLyricsSource = 'online-lyrics';

/// `lyricSource` written on a project whose lyrics were pasted by the user.
const String pastedLyricsSource = 'pasted-text';

/// One lyric found online for a song, ready to show and to save.
///
/// Unlike [OnlineLyricMatch], there is no recognised draft to compare with:
/// the user asked for the lyrics of a song that has none yet. The options are
/// therefore ranked by title, artist and recording length, and the user checks
/// the timing by listening (decision D-054).
class SongLyricsOption {
  final OnlineLyricCandidate candidate;

  /// The lyric with its timestamps; null when the site only had plain text
  /// or its timestamps could not be read.
  final LyricImportResult? timed;

  /// The same words without timestamps; always present.
  final LyricImportResult plain;

  /// Ranking score; higher is better. Only meaningful between options of the
  /// same lookup.
  final double score;

  /// Candidate title equals the wanted one after cleaning.
  final bool titleMatches;

  /// Candidate artist contains the wanted one (or the other way round).
  final bool artistMatches;

  /// Candidate length minus song length; null when either is unknown.
  final Duration? durationDifference;

  const SongLyricsOption({
    required this.candidate,
    required this.timed,
    required this.plain,
    required this.score,
    required this.titleMatches,
    required this.artistMatches,
    required this.durationDifference,
  });

  bool get hasTiming => timed != null;

  int get lineCount => plain.document.lines.length;

  /// The lyric was made for a recording whose length differs by more than
  /// [SongLyricsLookup.durationWarningThreshold]: probably another version,
  /// so its timestamps may not fit this audio.
  bool get durationMismatch {
    final difference = durationDifference;
    if (difference == null) return false;
    return difference.abs() > SongLyricsLookup.durationWarningThreshold;
  }

  /// Short, user-facing notes shown next to the option.
  List<String> get notes {
    final difference = durationDifference;
    return [
      hasTiming ? '带时间轴' : '纯文本',
      '$lineCount 行',
      if (difference != null && durationMismatch)
        '时长相差 ${difference.abs().inSeconds} 秒',
      if (!titleMatches) '歌名不完全一致',
    ];
  }
}

/// What a lookup for one song found.
class SongLyricsLookupResult {
  final OnlineLyricQuery query;
  final List<SongLyricsOption> options;
  final Map<OnlineLyricSourceKind, String> failures;

  const SongLyricsLookupResult({
    required this.query,
    required this.options,
    this.failures = const {},
  });

  bool get isEmpty => options.isEmpty;

  /// Nothing found and every site failed: most likely offline.
  bool get allSourcesFailed => options.isEmpty && failures.isNotEmpty;

  SongLyricsOption? get best => options.isEmpty ? null : options.first;
}

/// Finds the lyrics of a song on the lyric sites, preferring timed ones.
///
/// Only the title, the artist and the length leave the computer. Results are
/// cleaned of credits and headers by the same sanitizer 一键校对 uses, parsed
/// with the app's own LRC parser, and offered timed-first; each timed option
/// also carries a plain-text twin so the user can keep the words when the
/// timing turns out not to fit.
class SongLyricsLookup {
  final OnlineLyricSearchService search;
  final LyricFileImportService importer;
  final OnlineLyricSanitizer sanitizer;

  /// How many options the dialog offers at most.
  final int maxOptions;

  /// A difference in length above which the timing is flagged as suspect.
  static const Duration durationWarningThreshold = Duration(seconds: 5);

  const SongLyricsLookup({
    required this.search,
    required this.importer,
    this.sanitizer = const OnlineLyricSanitizer(),
    this.maxOptions = 8,
  });

  Future<SongLyricsLookupResult> find(OnlineLyricQuery query) async {
    final found = await search.search(query);
    return SongLyricsLookupResult(
      query: query,
      options: rank(found.candidates, query),
      failures: found.failures,
    );
  }

  /// Every usable candidate, best first, with identical lyrics from several
  /// sites collapsed into the best-scored one.
  List<SongLyricsOption> rank(
    List<OnlineLyricCandidate> candidates,
    OnlineLyricQuery query,
  ) {
    final options = <SongLyricsOption>[];
    for (final candidate in candidates) {
      final option = evaluate(candidate, query);
      if (option != null) options.add(option);
    }
    options.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    final unique = <SongLyricsOption>[];
    for (final option in options) {
      final key = _textKey(option.plain.document);
      if (key.isNotEmpty && !seen.add('${option.hasTiming}:$key')) continue;
      unique.add(option);
      if (unique.length >= maxOptions) break;
    }
    return unique;
  }

  /// One candidate as an option; null when nothing sung is left after the
  /// credits are removed (instrumental tracks, empty uploads).
  SongLyricsOption? evaluate(
    OnlineLyricCandidate candidate,
    OnlineLyricQuery query,
  ) {
    final cleaned = sanitizer.sanitize(
      candidate.lyricText,
      title: candidate.title.isEmpty ? query.title : candidate.title,
      artist: candidate.artist.isEmpty ? query.artist : candidate.artist,
    );
    if (cleaned.trim().isEmpty) return null;

    LyricImportResult? timed;
    if (sanitizer.isTimed(cleaned)) {
      timed = _parse(cleaned, 'lrc', candidate);
      final document = timed?.document;
      if (document == null || document.lines.isEmpty || document.isUntimed) {
        timed = null;
      }
    }
    final LyricImportResult plain;
    if (timed != null) {
      plain = untimedImportResult(timed);
    } else {
      final parsed = _parse(_withoutTags(cleaned), 'txt', candidate);
      if (parsed == null || parsed.document.lines.isEmpty) return null;
      plain = parsed;
    }

    final titleKey = _key(OnlineLyricQuery.cleanTitle(candidate.title));
    final wantedTitle = _key(query.title);
    final titleMatches = titleKey.isNotEmpty && titleKey == wantedTitle;
    final titleRelated =
        titleMatches ||
        (titleKey.isNotEmpty &&
            wantedTitle.isNotEmpty &&
            (titleKey.contains(wantedTitle) || wantedTitle.contains(titleKey)));
    final artistKey = _key(candidate.artist);
    final wantedArtist = _key(query.artist);
    final artistMatches =
        artistKey.isNotEmpty &&
        wantedArtist.isNotEmpty &&
        (artistKey.contains(wantedArtist) || wantedArtist.contains(artistKey));

    Duration? difference;
    final length = candidate.duration;
    final wantedLength = query.duration;
    if (length != null && wantedLength != null && length > Duration.zero) {
      difference = length - wantedLength;
    }

    var score = 0.0;
    if (titleMatches) {
      score += 0.45;
    } else if (titleRelated) {
      score += 0.25;
    }
    if (artistMatches) {
      score += 0.25;
    } else if (wantedArtist.isEmpty) {
      score += 0.1;
    }
    if (difference != null) {
      final seconds = difference.abs().inMilliseconds / 1000;
      if (seconds <= 2) {
        score += 0.2;
      } else if (seconds <= 5) {
        score += 0.15;
      } else if (seconds <= 15) {
        score += 0.05;
      } else if (seconds > 30) {
        score -= 0.15;
      }
    }
    if (timed != null) score += 0.08;

    return SongLyricsOption(
      candidate: candidate,
      timed: timed,
      plain: plain,
      score: score,
      titleMatches: titleMatches,
      artistMatches: artistMatches,
      durationDifference: difference,
    );
  }

  LyricImportResult? _parse(
    String text,
    String extension,
    OnlineLyricCandidate candidate,
  ) {
    try {
      final result = importer.parseText(text, extension: extension);
      return withOnlineProvenance(result, candidate);
    } on LyricImportException {
      return null;
    }
  }

  static final RegExp _leadingTags = RegExp(r'^(\s*\[[^\]]*\])+');

  /// Plain text that still has LRC metadata rows (`[ti:…]`) or stray tags.
  static String _withoutTags(String text) => [
    for (final line in text.split('\n'))
      if (line.replaceFirst(_leadingTags, '').trim().isNotEmpty)
        line.replaceFirst(_leadingTags, ''),
  ].join('\n');

  static String _key(String text) => text.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );

  static String _textKey(LyricDocument document) =>
      _key(document.lines.map((line) => line.text).join());
}

/// [result] with the lyric site, its id and the song it listed recorded in
/// the document metadata, so a wrong match can be traced afterwards.
LyricImportResult withOnlineProvenance(
  LyricImportResult result,
  OnlineLyricCandidate candidate,
) {
  final document = result.document;
  return LyricImportResult(
    document: document.copyWith(
      metadata: {
        ...document.metadata,
        'source': onlineLyricsSource,
        'onlineSource': candidate.source.name,
        'onlineSourceLabel': candidate.source.label,
        'onlineSourceId': candidate.sourceId,
        'onlineTitle': candidate.title,
        'onlineArtist': candidate.artist,
      },
    ),
    format: result.format,
    sourcePath: result.sourcePath,
    detectedEncoding: result.detectedEncoding,
    title: candidate.title.isEmpty ? result.title : candidate.title,
    artist: candidate.artist.isEmpty ? result.artist : candidate.artist,
    album: result.album,
    conflicts: result.conflicts,
  );
}

/// [result] as plain reference text: same words, no timestamps.
LyricImportResult untimedImportResult(LyricImportResult result) {
  return LyricImportResult(
    document: result.document.withoutTimestamps(),
    format: LyricImportFormat.plainText,
    sourcePath: result.sourcePath,
    detectedEncoding: result.detectedEncoding,
    title: result.title,
    artist: result.artist,
    album: result.album,
  );
}

/// [result] with a whole-lyric shift the user chose while checking the
/// timing; untimed results are returned unchanged.
LyricImportResult shiftedImportResult(
  LyricImportResult result,
  Duration offset,
) {
  if (offset == Duration.zero || result.document.isUntimed) return result;
  final document = result.document;
  return LyricImportResult(
    document: document.copyWith(
      globalOffset: (document.globalOffset ?? Duration.zero) + offset,
      metadata: {
        ...document.metadata,
        'previewOffsetMs': offset.inMilliseconds,
      },
    ),
    format: result.format,
    sourcePath: result.sourcePath,
    detectedEncoding: result.detectedEncoding,
    title: result.title,
    artist: result.artist,
    album: result.album,
    conflicts: result.conflicts,
  );
}

/// [result] with every line converted to [target] (简体 / 繁體); lines in
/// Japanese or Korean are left alone.
LyricImportResult scriptConvertedImportResult(
  LyricImportResult result,
  ChineseScriptTarget? target, {
  ChineseScriptConverter converter = const ChineseScriptConverter(),
}) {
  if (target == null) return result;
  final document = result.document;
  return LyricImportResult(
    document: document.copyWith(
      lines: [
        for (final line in document.lines)
          line.copyWith(text: _convertLine(converter, line.text, target)),
      ],
      metadata: {...document.metadata, 'scriptConvertedTo': target.name},
    ),
    format: result.format,
    sourcePath: result.sourcePath,
    detectedEncoding: result.detectedEncoding,
    title: result.title,
    artist: result.artist,
    album: result.album,
    conflicts: result.conflicts,
  );
}

String _convertLine(
  ChineseScriptConverter converter,
  String text,
  ChineseScriptTarget target,
) {
  final profile = converter.profile(text);
  if (profile.hasKanaOrHangul || profile.hanCount == 0) return text;
  return converter.convertLine(text, target);
}
