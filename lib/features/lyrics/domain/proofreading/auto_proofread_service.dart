import '../../../project/domain/models/lyric_document.dart';
import '../online/online_lyric_candidate.dart';
import '../online/online_lyric_matcher.dart';
import '../online/online_lyric_query.dart';
import 'one_click_proofread_use_case.dart';

/// Why 一键校对 ran without an online lyric.
enum AutoProofreadLyricStatus {
  /// A lyric matched the recording and corrected the draft.
  applied,

  /// Online search is not configured (tests, or turned off).
  searchUnavailable,

  /// The project has no usable song title to search for.
  noTitle,

  /// Every lyric site failed: usually no network.
  offline,

  /// The sites answered, but with no lyric for this title.
  notFound,

  /// Lyrics were found, but none matched what was recognised (another song
  /// with the same title, or a recording too different to trust).
  noMatch,

  /// A lyric matched, but applying it would have broken the timeline.
  rejected,
}

/// Everything one 一键校对 run found and did.
class AutoProofreadOutcome {
  final OneClickProofreadResult result;
  final AutoProofreadLyricStatus lyricStatus;
  final OnlineLyricQuery query;

  /// The best candidate, matched or not; shown when nothing was applied so
  /// the user can see what was considered.
  final OnlineLyricMatch? bestCandidate;

  /// Sites that failed, with a short reason.
  final Map<OnlineLyricSourceKind, String> failures;

  const AutoProofreadOutcome({
    required this.result,
    required this.lyricStatus,
    required this.query,
    this.bestCandidate,
    this.failures = const {},
  });

  bool get usedOnlineLyric => lyricStatus == AutoProofreadLyricStatus.applied;
}

/// 一键校对: find the song's lyric online, judge it against the draft, then
/// apply every safe correction in one pass ([OneClickProofreadUseCase]).
///
/// Without a network or a matching lyric the clean-up steps still run, so
/// the button always does something useful.
class AutoProofreadService {
  final OnlineLyricSearchService? search;
  final OnlineLyricMatcher matcher;
  final OneClickProofreadUseCase useCase;

  const AutoProofreadService({
    required this.search,
    required this.matcher,
    this.useCase = const OneClickProofreadUseCase(),
  });

  /// Whether a lyric can be searched for at all.
  bool get canSearch => search != null;

  /// The search derived from the project's name, artist and audio length.
  static OnlineLyricQuery queryFor({
    required String projectName,
    String? artist,
    Duration? audioDuration,
  }) => OnlineLyricQuery.fromProject(
    name: projectName,
    artist: artist,
    duration: audioDuration,
  );

  /// Searches every source for [query] and judges the results against
  /// [draft].
  Future<
    ({
      AutoProofreadLyricStatus status,
      OnlineLyricMatch? best,
      Map<OnlineLyricSourceKind, String> failures,
    })
  >
  findLyric({
    required LyricDocument draft,
    required OnlineLyricQuery query,
  }) async {
    const noFailures = <OnlineLyricSourceKind, String>{};
    final searchService = search;
    if (searchService == null) {
      return (
        status: AutoProofreadLyricStatus.searchUnavailable,
        best: null,
        failures: noFailures,
      );
    }
    if (!query.isSearchable) {
      return (
        status: AutoProofreadLyricStatus.noTitle,
        best: null,
        failures: noFailures,
      );
    }
    final found = await searchService.search(query);
    if (found.allSourcesFailed) {
      return (
        status: AutoProofreadLyricStatus.offline,
        best: null,
        failures: found.failures,
      );
    }
    final ranked = matcher.rank(
      draft: draft,
      candidates: found.candidates,
      query: query,
    );
    if (ranked.isEmpty) {
      return (
        status: AutoProofreadLyricStatus.notFound,
        best: null,
        failures: found.failures,
      );
    }
    final best = ranked.first;
    return (
      status: best.accepted
          ? AutoProofreadLyricStatus.applied
          : AutoProofreadLyricStatus.noMatch,
      best: best,
      failures: found.failures,
    );
  }

  Future<AutoProofreadOutcome> run({
    required LyricDocument draft,
    required OnlineLyricQuery query,
    Set<int> protectedIndices = const {},
    required DateTime appliedAt,
  }) async {
    final lyric = await findLyric(draft: draft, query: query);
    final reference = lyric.status == AutoProofreadLyricStatus.applied
        ? lyric.best
        : null;
    final result = useCase.build(
      draft: draft,
      reference: reference,
      protectedIndices: protectedIndices,
      audioDuration: query.duration,
      appliedAt: appliedAt,
    );
    return AutoProofreadOutcome(
      result: result,
      lyricStatus: result.referenceRejected
          ? AutoProofreadLyricStatus.rejected
          : lyric.status,
      query: query,
      bestCandidate: lyric.best,
      failures: lyric.failures,
    );
  }
}
