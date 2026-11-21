import 'dart:math' as math;

import '../../../project/domain/models/lyric_document.dart';
import '../models/chinese_script_preference.dart';
import '../models/reference_lyric_input.dart';
import '../models/reference_lyric_line.dart';
import '../services/chinese_script_unification_service.dart';
import '../services/lyric_alignment_service.dart';
import '../services/reference_lyric_text_parser.dart';
import '../text/chinese_script_converter.dart';
import 'online_lyric_candidate.dart';
import 'online_lyric_query.dart';
import 'online_lyric_sanitizer.dart';

/// A candidate lyric judged against the recognised draft.
class OnlineLyricMatch {
  final OnlineLyricCandidate candidate;

  /// The cleaned lyric, in the draft's Chinese script, ready for reference
  /// alignment. Timed only when its timestamps were moved onto the audio.
  final ReferenceLyricInput input;

  /// Share of the draft's sung characters on rows the lyric matches.
  final double draftCoverage;

  /// Share of the lyric's rows that match a draft row.
  final double referenceCoverage;
  final double score;

  /// Good enough to correct the draft without asking: the same song, not
  /// merely the same artist or title.
  final bool accepted;

  /// How far the lyric's timestamps were moved to fit the audio; null when
  /// the lyric was untimed or its timing was dropped.
  final Duration? timingOffset;

  /// The lyric had timestamps, but they did not agree with the recording
  /// (another version or a careless upload), so only its text is used.
  final bool timingDropped;

  const OnlineLyricMatch({
    required this.candidate,
    required this.input,
    required this.draftCoverage,
    required this.referenceCoverage,
    required this.score,
    required this.accepted,
    this.timingOffset,
    this.timingDropped = false,
  });
}

/// Picks the online lyric that belongs to the recognised song.
///
/// Titles and artists on lyric sites are unreliable (covers, live versions,
/// the same title by another singer), so the decision rests on the text: the
/// lyric is aligned with the draft row by row, and only a lyric that covers
/// most of what was recognised is accepted. Title, artist and duration only
/// break ties between good matches.
class OnlineLyricMatcher {
  final ReferenceLyricTextParser parser;
  final OnlineLyricSanitizer sanitizer;
  final ChineseScriptConverter converter;
  final LyricAlignmentService alignment;

  /// At least half of the draft's sung characters must be on matched rows.
  static const double minimumDraftCoverage = 0.5;

  /// And at least a third of the lyric's rows must be found in the draft,
  /// which rejects a long unrelated lyric that happens to share a chorus.
  static const double minimumReferenceCoverage = 0.35;

  /// Reference timestamps are kept only when they agree with the draft to
  /// within this median deviation after one common shift.
  static const Duration maximumTimingSpread = Duration(milliseconds: 1200);

  const OnlineLyricMatcher({
    required this.parser,
    this.sanitizer = const OnlineLyricSanitizer(),
    this.converter = const ChineseScriptConverter(),
    this.alignment = const LyricAlignmentService(),
  });

  /// Every usable candidate, best first.
  List<OnlineLyricMatch> rank({
    required LyricDocument draft,
    required List<OnlineLyricCandidate> candidates,
    required OnlineLyricQuery query,
  }) {
    final target = draftScriptTarget(draft);
    final matches = <OnlineLyricMatch>[];
    for (final candidate in candidates) {
      final match = evaluate(
        draft: draft,
        candidate: candidate,
        query: query,
        scriptTarget: target,
      );
      if (match != null) matches.add(match);
    }
    matches.sort((a, b) {
      if (a.accepted != b.accepted) return a.accepted ? -1 : 1;
      return b.score.compareTo(a.score);
    });
    return matches;
  }

  /// Judges one candidate; null when it has no usable lyric rows.
  OnlineLyricMatch? evaluate({
    required LyricDocument draft,
    required OnlineLyricCandidate candidate,
    required OnlineLyricQuery query,
    ChineseScriptTarget? scriptTarget,
  }) {
    final cleaned = sanitizer.sanitize(
      candidate.lyricText,
      title: candidate.title.isEmpty ? query.title : candidate.title,
      artist: candidate.artist.isEmpty ? query.artist : candidate.artist,
    );
    if (cleaned.isEmpty) return null;
    final ReferenceLyricInput parsed;
    try {
      parsed = parser.parsePasted(
        cleaned,
        title: candidate.title,
        artist: candidate.artist,
      );
    } on ReferenceLyricParseException {
      return null;
    }
    final lines = [
      for (final line in parsed.lines)
        ReferenceLyricLine(
          text: _inScript(line.text, scriptTarget),
          startTime: line.startTime,
          endTime: line.endTime,
        ),
    ];
    if (lines.isEmpty) return null;

    final aligned = alignment.align(document: draft, referenceLines: lines);
    final draftCoverage = _draftCoverage(draft, aligned);
    final matchedReferences = aligned.entries
        .where((entry) => entry.asrLineIndex != null)
        .length;
    final referenceCoverage = aligned.entries.isEmpty
        ? 0.0
        : matchedReferences / aligned.entries.length;

    Duration? offset;
    var timingDropped = false;
    var finalLines = lines;
    var timed = parsed.timed;
    if (parsed.timed) {
      offset = _timingOffset(draft, aligned);
      if (offset == null) {
        timingDropped = true;
        timed = false;
        finalLines = [
          for (final line in lines) ReferenceLyricLine(text: line.text),
        ];
      } else {
        finalLines = [
          for (final line in lines)
            ReferenceLyricLine(
              text: line.text,
              startTime: _shift(line.startTime, offset),
              endTime: _shift(line.endTime, offset),
            ),
        ];
      }
    }

    final sungDraftLines = draft.lines
        .where((line) => LyricAlignmentService.normalizeLine(line.text) != '')
        .length;
    final accepted =
        sungDraftLines >= 2 &&
        finalLines.length >= 2 &&
        draftCoverage >= minimumDraftCoverage &&
        referenceCoverage >= minimumReferenceCoverage;
    final score =
        draftCoverage * 0.6 +
        referenceCoverage * 0.25 +
        _metadataScore(candidate, query) +
        (timed ? 0.01 : 0);

    return OnlineLyricMatch(
      candidate: candidate,
      input: ReferenceLyricInput(
        lines: List.unmodifiable(finalLines),
        timed: timed,
        format: timed ? parsed.format : 'plainText',
        offset: offset ?? Duration.zero,
        title: candidate.title,
        artist: candidate.artist,
        conflicts: timed ? parsed.conflicts : const [],
        warnings: timed ? parsed.warnings : const [],
      ),
      draftCoverage: draftCoverage,
      referenceCoverage: referenceCoverage,
      score: score,
      accepted: accepted,
      timingOffset: timed ? offset : null,
      timingDropped: timingDropped,
    );
  }

  /// The Chinese script the draft is written in, so a lyric in the other
  /// script corrects words instead of rewriting every character. Null for
  /// Japanese or Korean drafts and when the draft gives no evidence.
  static ChineseScriptTarget? draftScriptTarget(LyricDocument draft) {
    if (ChineseLanguageTag.isChinese(draft.language) == false) return null;
    const service = ChineseScriptUnificationService();
    final profile = service.profileDocument(draft);
    final kanaLines = profile.japaneseOrKoreanLines;
    final hanLines = profile.hanLines + kanaLines;
    if (hanLines == 0) return null;
    if (kanaLines / hanLines >=
        ChineseScriptUnificationService.japaneseOrKoreanLineShare) {
      return null;
    }
    final implied = ChineseLanguageTag.impliedTarget(draft.language);
    if (profile.simplifiedLines > profile.traditionalLines) {
      return ChineseScriptTarget.simplified;
    }
    if (profile.traditionalLines > profile.simplifiedLines) {
      if (implied == ChineseScriptTarget.traditionalHongKong ||
          ChineseLanguageTag.isCantonese(draft.language)) {
        return ChineseScriptTarget.traditionalHongKong;
      }
      return ChineseScriptTarget.traditionalTaiwan;
    }
    return implied;
  }

  String _inScript(String text, ChineseScriptTarget? target) {
    if (target == null) return text;
    final profile = converter.profile(text);
    if (profile.hasKanaOrHangul || profile.hanCount == 0) return text;
    return converter.convertLine(text, target);
  }

  static double _draftCoverage(
    LyricDocument draft,
    LyricAlignmentResult aligned,
  ) {
    var total = 0;
    var matched = 0;
    for (final line in aligned.asrLines) {
      final weight = LyricAlignmentService.normalizeLine(
        draft.lines[line.asrLineIndex].text,
      ).runes.length;
      total += weight;
      if (line.status != AsrLineAlignmentStatus.unmatched) matched += weight;
    }
    return total == 0 ? 0 : matched / total;
  }

  /// One shift that moves the lyric's timestamps onto the recording, from
  /// rows matched with confidence; null when there are too few such rows or
  /// they disagree, which means the lyric was timed for another version.
  static Duration? _timingOffset(
    LyricDocument draft,
    LyricAlignmentResult aligned,
  ) {
    final deltas = <int>[];
    for (final entry in aligned.entries) {
      final index = entry.asrLineIndex;
      final start = entry.startTime;
      if (index == null || start == null || !entry.referenceHasTimestamp) {
        continue;
      }
      if (entry.ambiguous || entry.structuralMismatch) continue;
      if (entry.status != ReferenceLineAlignmentStatus.identical &&
          entry.status != ReferenceLineAlignmentStatus.replace) {
        continue;
      }
      deltas.add(
        draft.lines[index].startTime.inMilliseconds - start.inMilliseconds,
      );
    }
    if (deltas.length < 3) return null;
    final median = _median(deltas);
    final spread = _median([for (final delta in deltas) (delta - median).abs()]);
    if (spread > maximumTimingSpread.inMilliseconds) return null;
    return Duration(milliseconds: median);
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static Duration? _shift(Duration? value, Duration offset) {
    if (value == null) return null;
    final shifted = value + offset;
    return shifted.isNegative ? Duration.zero : shifted;
  }

  static double _metadataScore(
    OnlineLyricCandidate candidate,
    OnlineLyricQuery query,
  ) {
    var score = 0.0;
    final title = _key(OnlineLyricQuery.cleanTitle(candidate.title));
    final wantedTitle = _key(query.title);
    if (title.isNotEmpty && wantedTitle.isNotEmpty) {
      if (title == wantedTitle) {
        score += 0.06;
      } else if (title.contains(wantedTitle) || wantedTitle.contains(title)) {
        score += 0.03;
      }
    }
    final artist = _key(candidate.artist);
    final wantedArtist = _key(query.artist);
    if (artist.isNotEmpty &&
        wantedArtist.isNotEmpty &&
        (artist.contains(wantedArtist) || wantedArtist.contains(artist))) {
      score += 0.04;
    }
    final duration = candidate.duration;
    final wantedDuration = query.duration;
    if (duration != null && wantedDuration != null) {
      final difference = (duration - wantedDuration).inMilliseconds.abs();
      if (difference <= 3000) {
        score += 0.05;
      } else if (difference <= 10000) {
        score += 0.025;
      }
    }
    return math.min(score, 0.15);
  }

  static String _key(String text) => const ChineseScriptConverter()
      .foldForComparison(text.toLowerCase())
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
}
