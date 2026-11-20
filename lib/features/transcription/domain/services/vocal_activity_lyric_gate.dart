import 'dart:math' as math;

import '../../../lyrics/domain/models/secondary_only_suggestion.dart';
import '../../../lyrics/domain/models/vocal_check_record.dart';
import '../../../lyrics/domain/services/lyric_indexed_review_metadata.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../models/vocal_activity.dart';

/// Why the vocal check left a draft as recognised.
enum VocalCheckSkipReason {
  /// Recognition did not listen to a vocal stem; the mix is loud everywhere.
  notVocalInput,

  /// The stem could not be read (missing, not a 16-bit PCM WAV).
  unreadableAudio,

  /// See [VocalActivityProfile.unreliability].
  unreliableProfile,

  /// The draft has no timed rows.
  noLines,

  /// So many rows have no singing that the timeline, not the rows, is
  /// probably wrong; nothing is deleted on a guess.
  tooManySilentLines,

  /// The check itself failed; recognition keeps its draft.
  failed,
}

/// What the vocal check did, for `metadata.transcription.vocalCheck`.
class VocalCheckReport {
  final bool applied;
  final VocalCheckSkipReason? skipReason;
  final String? audioPath;
  final VocalActivityProfile? profile;
  final LyricVocalCheckRecord record;

  /// Rows the check would have deleted when it gave up with
  /// [VocalCheckSkipReason.tooManySilentLines].
  final int silentLines;
  final String? error;

  const VocalCheckReport._({
    required this.applied,
    this.skipReason,
    this.audioPath,
    this.profile,
    this.record = const LyricVocalCheckRecord(),
    this.silentLines = 0,
    this.error,
  });

  const VocalCheckReport.applied({
    required String audioPath,
    required VocalActivityProfile profile,
    required LyricVocalCheckRecord record,
  }) : this._(
         applied: true,
         audioPath: audioPath,
         profile: profile,
         record: record,
       );

  const VocalCheckReport.skipped(
    VocalCheckSkipReason reason, {
    String? audioPath,
    VocalActivityProfile? profile,
    int silentLines = 0,
    String? error,
  }) : this._(
         applied: false,
         skipReason: reason,
         audioPath: audioPath,
         profile: profile,
         silentLines: silentLines,
         error: error,
       );

  Map<String, Object?> toJson() => {
    'applied': applied,
    'skipReason': skipReason?.name,
    'audioPath': audioPath,
    'removedLines': record.removedLines.length,
    'retimedLines': record.retimedLines,
    'uncoveredSpans': record.uncoveredSpans.length,
    if (silentLines > 0) 'silentLines': silentLines,
    'profile': profile?.summaryJson(),
    'error': ?error,
  };
}

/// A draft after the vocal check, with what was done to it.
class VocalCheckResult {
  final LyricDocument document;
  final VocalCheckReport report;

  const VocalCheckResult(this.document, this.report);

  /// The draft unchanged, with the reason.
  VocalCheckResult.unchanged(this.document, this.report);
}

/// Applies a [VocalActivityProfile] of the recognised vocal stem to a fresh
/// draft (D-044).
///
/// * A row with (practically) no singing between its start and end is a
///   recogniser inventing lyrics over an intro, interlude or outro, and is
///   deleted. Rows near the end of the audio the profile does not cover are
///   kept. When more than [maximumSilentShare] of the rows look silent, the
///   timeline rather than the rows is suspect and nothing changes.
/// * A row that starts well before its singing starts, or ends well after it
///   stops, is pulled in to the singing (with a short lead-in and release),
///   but never past its own word timing. Rows only the second engine heard
///   keep their times: their review record matches them by exact timing.
/// * Stretches of singing no row covers are recorded as probably missed
///   lyrics.
///
/// Row-indexed review evidence (the second engine's candidates and
/// suggestions) follows the rows that remain.
class VocalActivityLyricGate {
  const VocalActivityLyricGate({
    this.timingSlack = const Duration(milliseconds: 200),
    this.minimumVoiced = const Duration(milliseconds: 150),
    this.maximumSilentShare = 0.35,
    this.alwaysAllowedSilentLines = 3,
    this.minimumLeadingSilence = const Duration(milliseconds: 400),
    this.minimumTrailingSilence = const Duration(milliseconds: 600),
    this.leadIn = const Duration(milliseconds: 120),
    this.release = const Duration(milliseconds: 200),
    this.minimumRetimedLength = const Duration(milliseconds: 300),
    this.coverTolerance = const Duration(milliseconds: 300),
    this.uncoveredJoinGap = const Duration(milliseconds: 800),
    this.minimumUncoveredVoiced = const Duration(milliseconds: 1200),
  });

  /// Recognisers' row times are approximate; singing this close outside a
  /// row still counts as the row's.
  final Duration timingSlack;

  /// Less singing than this within a row (plus [timingSlack]) is none.
  final Duration minimumVoiced;
  final double maximumSilentShare;

  /// Up to this many silent rows are deleted even in a short draft, where
  /// [maximumSilentShare] alone would protect the usual fake intro,
  /// interlude and outro lines.
  final int alwaysAllowedSilentLines;

  final Duration minimumLeadingSilence;
  final Duration minimumTrailingSilence;
  final Duration leadIn;
  final Duration release;
  final Duration minimumRetimedLength;

  /// A row this close to singing covers it.
  final Duration coverTolerance;

  /// Uncovered singing this close together is one missed stretch.
  final Duration uncoveredJoinGap;

  /// A missed stretch needs at least this much singing.
  final Duration minimumUncoveredVoiced;

  VocalCheckResult apply(
    LyricDocument draft,
    VocalActivityProfile profile, {
    required String audioPath,
  }) {
    if (!profile.isReliable) {
      return VocalCheckResult.unchanged(
        draft,
        VocalCheckReport.skipped(
          VocalCheckSkipReason.unreliableProfile,
          audioPath: audioPath,
          profile: profile,
        ),
      );
    }
    final timed = [
      for (var index = 0; index < draft.lines.length; index++)
        if (_isTimed(draft.lines[index])) index,
    ];
    if (timed.isEmpty) {
      return VocalCheckResult.unchanged(
        draft,
        VocalCheckReport.skipped(
          VocalCheckSkipReason.noLines,
          audioPath: audioPath,
          profile: profile,
        ),
      );
    }

    final silent = <int>{
      for (final index in timed)
        if (_isSilent(draft.lines[index], profile)) index,
    };
    final allowed = math.max(
      alwaysAllowedSilentLines,
      (timed.length * maximumSilentShare).floor(),
    );
    if (silent.length > allowed) {
      return VocalCheckResult.unchanged(
        draft,
        VocalCheckReport.skipped(
          VocalCheckSkipReason.tooManySilentLines,
          audioPath: audioPath,
          profile: profile,
          silentLines: silent.length,
        ),
      );
    }

    final suggested = SecondaryOnlySuggestion.resolve(draft).keys.toSet();
    final lines = <LyricLine>[];
    final removed = <LyricVocalCheckRemovedLine>[];
    final newIndex = <int, int>{};
    var retimed = 0;
    for (var index = 0; index < draft.lines.length; index++) {
      final line = draft.lines[index];
      if (silent.contains(index)) {
        removed.add(
          LyricVocalCheckRemovedLine(
            text: line.text,
            start: line.startTime,
            end: line.endTime,
          ),
        );
        continue;
      }
      final adjusted = _isTimed(line) && !suggested.contains(index)
          ? _retime(line, profile)
          : line;
      if (!identical(adjusted, line)) retimed++;
      newIndex[index] = lines.length;
      lines.add(adjusted);
    }

    final record = LyricVocalCheckRecord(
      removedLines: removed,
      retimedLines: retimed,
      uncoveredSpans: _uncovered(lines, profile),
    );
    final metadata = removed.isEmpty
        ? Map<String, dynamic>.from(draft.metadata)
        : LyricIndexedReviewMetadata.remapped(
            draft.metadata,
            (index) => newIndex[index],
          );
    metadata[LyricVocalCheckRecord.metadataKey] = record.toJson();
    return VocalCheckResult(
      draft.copyWith(lines: lines, metadata: metadata),
      VocalCheckReport.applied(
        audioPath: audioPath,
        profile: profile,
        record: record,
      ),
    );
  }

  static bool _isTimed(LyricLine line) =>
      line.text.trim().isNotEmpty && line.endTime > line.startTime;

  bool _isSilent(LyricLine line, VocalActivityProfile profile) {
    // The profile ends where the decoded audio ends; a row reaching past it
    // cannot be judged.
    if (line.endTime > profile.duration) return false;
    final start = line.startTime - timingSlack;
    final voiced = profile.voicedWithin(
      start.isNegative ? Duration.zero : start,
      line.endTime + timingSlack,
    );
    return voiced < minimumVoiced;
  }

  LyricLine _retime(LyricLine line, VocalActivityProfile profile) {
    if (line.endTime > profile.duration) return line;
    final onset = profile.firstVoiceIn(line.startTime, line.endTime);
    final offset = profile.lastVoiceIn(line.startTime, line.endTime);
    if (onset == null || offset == null) return line;

    var start = line.startTime;
    var end = line.endTime;
    if (onset - line.startTime >= minimumLeadingSilence) {
      start = onset - leadIn;
    }
    if (line.endTime - offset >= minimumTrailingSilence) {
      end = offset + release;
    }
    // Word timing comes from an aligner and outranks the row's estimate.
    final words = line.words;
    if (words.isNotEmpty) {
      final firstWord = words.first.start;
      final lastWord = words.last.end;
      if (start > firstWord) start = firstWord;
      if (end < lastWord) end = lastWord;
    }
    if (start < line.startTime) start = line.startTime;
    if (end > line.endTime) end = line.endTime;
    if (start == line.startTime && end == line.endTime) return line;
    if (end - start < minimumRetimedLength) return line;
    return line.copyWith(startTime: start, endTime: end);
  }

  List<LyricVocalCheckSpan> _uncovered(
    List<LyricLine> lines,
    VocalActivityProfile profile,
  ) {
    final covers = [
      for (final line in lines)
        if (_isTimed(line))
          LyricVocalCheckSpan(
            line.startTime - coverTolerance,
            line.endTime + coverTolerance,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // Singing minus the rows' spans.
    final pieces = <LyricVocalCheckSpan>[];
    for (final region in profile.regions) {
      var cursor = region.start;
      for (final cover in covers) {
        if (cover.end <= cursor) continue;
        if (cover.start >= region.end) break;
        if (cover.start > cursor) {
          pieces.add(LyricVocalCheckSpan(cursor, cover.start));
        }
        if (cover.end > cursor) cursor = cover.end;
        if (cursor >= region.end) break;
      }
      if (cursor < region.end) {
        pieces.add(LyricVocalCheckSpan(cursor, region.end));
      }
    }

    // Pieces close together form one missed stretch; keep the substantial
    // ones.
    final stretches = <LyricVocalCheckSpan>[];
    var voiced = Duration.zero;
    LyricVocalCheckSpan? current;
    void close() {
      final span = current;
      if (span != null && voiced >= minimumUncoveredVoiced) {
        stretches.add(span);
      }
    }

    for (final piece in pieces) {
      final open = current;
      if (open != null &&
          piece.start - open.end <= uncoveredJoinGap &&
          // A row between two pieces keeps them apart.
          !covers.any(
            (cover) => cover.start < piece.start && cover.end > open.end,
          )) {
        current = LyricVocalCheckSpan(open.start, piece.end);
        voiced += piece.duration;
      } else {
        close();
        current = piece;
        voiced = piece.duration;
      }
    }
    close();
    return stretches;
  }
}
