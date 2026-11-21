import 'dart:async';

import 'online_lyric_query.dart';

/// Where a fetched lyric came from.
///
/// The label is shown to the user next to every applied result, so a wrong
/// match can be traced back to its source.
enum OnlineLyricSourceKind {
  lrclib('LRCLIB'),
  netease('网易云音乐'),
  kugou('酷狗音乐');

  const OnlineLyricSourceKind(this.label);

  final String label;
}

/// One lyric found online, before it is compared with the draft.
class OnlineLyricCandidate {
  final OnlineLyricSourceKind source;

  /// The source's own id for the lyric or song, kept for provenance.
  final String sourceId;
  final String title;
  final String artist;

  /// The length of the recording the lyric was made for, when the source
  /// says so.
  final Duration? duration;

  /// The lyric as the source returned it: LRC when it is synced, plain text
  /// otherwise. Credits and metadata are removed later by the sanitizer.
  final String lyricText;

  const OnlineLyricCandidate({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.artist,
    required this.lyricText,
    this.duration,
  });

  /// "歌名 - 歌手 · 来源", as shown in the result dialog.
  String get displayName {
    final name = artist.trim().isEmpty ? title : '$title - $artist';
    return '$name · ${source.label}';
  }
}

/// Searches one lyric site.
///
/// Implementations return every candidate they could download; they throw
/// only when the site could not be reached at all. Ranking against the draft
/// happens later, in one place, so every source is judged the same way.
abstract interface class OnlineLyricSource {
  OnlineLyricSourceKind get kind;

  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query);
}

/// What a search across every source produced.
class OnlineLyricSearchResult {
  final List<OnlineLyricCandidate> candidates;

  /// Sources that failed, with a short reason for the summary.
  final Map<OnlineLyricSourceKind, String> failures;

  const OnlineLyricSearchResult({
    required this.candidates,
    this.failures = const {},
  });

  static const empty = OnlineLyricSearchResult(candidates: []);

  /// Every source failed, which usually means the computer is offline.
  bool get allSourcesFailed => candidates.isEmpty && failures.isNotEmpty;
}

/// Queries every lyric source at once and merges what they return.
///
/// A source that is slow or down only costs its own [timeout]; the others
/// still contribute. Only the song title, artist and duration leave the
/// computer — never the audio or the recognised lyrics.
class OnlineLyricSearchService {
  final List<OnlineLyricSource> sources;
  final Duration timeout;

  const OnlineLyricSearchService({
    required this.sources,
    this.timeout = const Duration(seconds: 12),
  });

  Future<OnlineLyricSearchResult> search(OnlineLyricQuery query) async {
    if (!query.isSearchable || sources.isEmpty) {
      return OnlineLyricSearchResult.empty;
    }
    final failures = <OnlineLyricSourceKind, String>{};
    final batches = await Future.wait([
      for (final source in sources)
        source
            .search(query)
            .timeout(timeout)
            .then<List<OnlineLyricCandidate>>(
              (found) => found,
              onError: (Object error) {
                failures[source.kind] = error is TimeoutException
                    ? '连接超时'
                    : _shortReason(error);
                return const <OnlineLyricCandidate>[];
              },
            ),
    ]);
    final seen = <String>{};
    final candidates = <OnlineLyricCandidate>[];
    for (final batch in batches) {
      for (final candidate in batch) {
        if (candidate.lyricText.trim().isEmpty) continue;
        if (!seen.add('${candidate.source.name}:${candidate.sourceId}')) {
          continue;
        }
        candidates.add(candidate);
      }
    }
    return OnlineLyricSearchResult(
      candidates: List.unmodifiable(candidates),
      failures: Map.unmodifiable(failures),
    );
  }

  static String _shortReason(Object error) {
    final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }
}
