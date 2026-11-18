import '../../../project/domain/models/lyric_document.dart';
import 'asr_segment_loop_detector.dart';

/// What the fusion step did with one Whisper loop.
enum WhisperLoopVerdict {
  /// The second engine heard distinct, loop-free lyrics over the same audio;
  /// its rows replace the looped Whisper rows and are queued for review.
  replacedBySecondary,

  /// The second engine hears the same repetition: the lyric really repeats.
  keptAsSung,

  /// No usable second opinion and the repetition is beyond what songs do:
  /// one repetition is kept, the rest removed, and the kept rows flagged.
  collapsedUnverified,

  /// No usable second opinion and the repetition could be sung: the rows
  /// stay and are flagged for listening.
  flaggedOnly,
}

/// One loop and how it was resolved.
class WhisperLoopDecision {
  final AsrSegmentLoop loop;
  final WhisperLoopVerdict verdict;

  /// Second-engine rows (indices into the secondary list) that now stand in
  /// for the loop.
  final List<int> secondaryIndices;

  /// Rows of the secondary engine over the loop that repeat the looped text.
  final int secondaryMatchingRows;

  /// Secondary rows over the loop's audio.
  final int secondaryRowsInSpan;

  /// Whether the secondary rows over the loop loop themselves.
  final bool secondaryLoops;

  const WhisperLoopDecision({
    required this.loop,
    required this.verdict,
    this.secondaryIndices = const [],
    this.secondaryMatchingRows = 0,
    this.secondaryRowsInSpan = 0,
    this.secondaryLoops = false,
  });

  /// Stable reason code for review candidates and diagnostics.
  String get reason => switch (verdict) {
    WhisperLoopVerdict.replacedBySecondary =>
      'whisper_cross_segment_loop_replaced_by_qwen',
    WhisperLoopVerdict.keptAsSung => 'whisper_repetition_confirmed_by_qwen',
    WhisperLoopVerdict.collapsedUnverified =>
      'whisper_cross_segment_loop_collapsed',
    WhisperLoopVerdict.flaggedOnly => 'whisper_cross_segment_repetition',
  };

  Map<String, dynamic> toMetadata() => {
    ...loop.toMetadata(),
    'verdict': verdict.name,
    'reason': reason,
    'secondaryRowsInSpan': secondaryRowsInSpan,
    'secondaryMatchingRows': secondaryMatchingRows,
    'secondaryLoops': secondaryLoops,
    if (secondaryIndices.isNotEmpty) 'secondaryIndices': secondaryIndices,
  };
}

/// A row of the arbitrated timeline that needs a person's attention.
class WhisperLoopReviewRow {
  /// Index in [WhisperLoopArbitration.lines].
  final int lineIndex;
  final WhisperLoopDecision decision;

  /// The Whisper text the row stands in for (the looped unit).
  final String loopedText;

  /// Whether the row's text comes from the second engine.
  final bool fromSecondary;

  const WhisperLoopReviewRow({
    required this.lineIndex,
    required this.decision,
    required this.loopedText,
    required this.fromSecondary,
  });
}

class WhisperLoopArbitration {
  /// Whisper's rows with every resolved loop applied.
  final List<LyricLine> lines;
  final List<WhisperLoopDecision> decisions;
  final List<WhisperLoopReviewRow> reviewRows;

  /// For each row of [lines], the index of the Whisper row it came from, or
  /// null for a row taken from the second engine.
  final List<int?> sourceIndices;

  const WhisperLoopArbitration({
    required this.lines,
    required this.decisions,
    required this.reviewRows,
    required this.sourceIndices,
  });

  bool get changed => decisions.any(
    (decision) =>
        decision.verdict == WhisperLoopVerdict.replacedBySecondary ||
        decision.verdict == WhisperLoopVerdict.collapsedUnverified,
  );

  List<Map<String, dynamic>> toMetadata() => [
    for (final decision in decisions) decision.toMetadata(),
  ];
}

/// Resolves Whisper loops that survived the history-free re-decode by asking
/// the independent second engine what it heard over the same audio.
///
/// Qwen decodes every 30 s chunk on its own with no text carried between
/// chunks, so it cannot inherit Whisper's self-conditioning loop. Three
/// outcomes are possible over a loop's audio:
///
/// * Qwen has loop-free rows that do not repeat the looped text — Whisper is
///   stuck; Qwen's rows replace the loop and every one is queued for review.
/// * Qwen repeats the looped text about as often — the song repeats; keep.
/// * Qwen has nothing usable there (no rows, or it loops too) — a strong loop
///   is cut down to one repetition and flagged; a weak one is only flagged.
class WhisperLoopArbiter {
  /// Confidence ceiling for rows the arbiter inserts or keeps under doubt,
  /// matching the ceiling used for secondary-only suggestions.
  static const int reviewConfidenceCeiling = 60;

  /// Token overlap at which a secondary row counts as the looped text.
  static const double matchingOverlap = 0.6;

  final AsrSegmentLoopDetector detector;

  const WhisperLoopArbiter({this.detector = const AsrSegmentLoopDetector()});

  WhisperLoopArbitration arbitrate({
    required List<LyricLine> primary,
    List<LyricLine>? secondary,
  }) {
    final loops = detector.detect(primary);
    if (loops.isEmpty) {
      return WhisperLoopArbitration(
        lines: primary,
        decisions: const [],
        reviewRows: const [],
        sourceIndices: [for (var i = 0; i < primary.length; i++) i],
      );
    }

    final decisions = <WhisperLoopDecision>[];
    final lines = <LyricLine>[];
    final sources = <int?>[];
    final reviewRows = <WhisperLoopReviewRow>[];
    final usedSecondary = <int>{};
    var next = 0;
    for (final loop in loops) {
      for (; next < loop.leadInIndex; next++) {
        lines.add(primary[next]);
        sources.add(next);
      }
      final decision = _decide(loop, secondary, usedSecondary);
      decisions.add(decision);
      final loopedText = loop.unitText.join(' / ');
      // The compressed lead-in is only replaced together with the loop; any
      // other verdict keeps those rows as Whisper wrote them.
      if (decision.verdict != WhisperLoopVerdict.replacedBySecondary) {
        for (var i = loop.leadInIndex; i < loop.firstIndex; i++) {
          lines.add(primary[i]);
          sources.add(i);
        }
      }
      switch (decision.verdict) {
        case WhisperLoopVerdict.replacedBySecondary:
          usedSecondary.addAll(decision.secondaryIndices);
          for (final secondaryIndex in decision.secondaryIndices) {
            final row = secondary![secondaryIndex];
            reviewRows.add(
              WhisperLoopReviewRow(
                lineIndex: lines.length,
                decision: decision,
                loopedText: loopedText,
                fromSecondary: true,
              ),
            );
            lines.add(_underReview(row));
            sources.add(null);
          }
        case WhisperLoopVerdict.keptAsSung:
          for (var i = loop.firstIndex; i < loop.endIndex; i++) {
            lines.add(primary[i]);
            sources.add(i);
          }
        case WhisperLoopVerdict.collapsedUnverified:
          for (
            var i = loop.firstIndex;
            i < loop.firstIndex + loop.blockRows;
            i++
          ) {
            reviewRows.add(
              WhisperLoopReviewRow(
                lineIndex: lines.length,
                decision: decision,
                loopedText: loopedText,
                fromSecondary: false,
              ),
            );
            lines.add(_underReview(primary[i]));
            sources.add(i);
          }
        case WhisperLoopVerdict.flaggedOnly:
          for (var i = loop.firstIndex; i < loop.endIndex; i++) {
            if (i == loop.firstIndex) {
              reviewRows.add(
                WhisperLoopReviewRow(
                  lineIndex: lines.length,
                  decision: decision,
                  loopedText: loopedText,
                  fromSecondary: false,
                ),
              );
            }
            lines.add(primary[i]);
            sources.add(i);
          }
      }
      next = loop.endIndex;
    }
    for (; next < primary.length; next++) {
      lines.add(primary[next]);
      sources.add(next);
    }

    return WhisperLoopArbitration(
      lines: List.unmodifiable(lines),
      decisions: List.unmodifiable(decisions),
      reviewRows: List.unmodifiable(reviewRows),
      sourceIndices: List.unmodifiable(sources),
    );
  }

  WhisperLoopDecision _decide(
    AsrSegmentLoop loop,
    List<LyricLine>? secondary,
    Set<int> usedSecondary,
  ) {
    // Only a strong loop that is not a short chant may lose rows. Chants
    // ("hey", "na na") legitimately repeat many times and Qwen is known to
    // drop repeated chants (D-025), so they are only ever flagged.
    final mayRemoveRows = loop.strong && !isChantLike(loop);
    final noEvidence = mayRemoveRows
        ? WhisperLoopVerdict.collapsedUnverified
        : WhisperLoopVerdict.flaggedOnly;
    if (secondary == null) {
      return WhisperLoopDecision(loop: loop, verdict: noEvidence);
    }

    final inSpan = <int>[
      for (var index = 0; index < secondary.length; index++)
        if (!usedSecondary.contains(index) &&
            _mostlyInside(secondary[index], loop.spanStart, loop.end) &&
            AsrSegmentLoopDetector.loopKey(secondary[index].text).isNotEmpty)
          index,
    ];
    final spanRows = [for (final index in inSpan) secondary[index]];
    final secondaryLoops = detector
        .detect(spanRows)
        .any((found) => found.strong);
    final heard = heardRepeats(loop, spanRows);

    WhisperLoopDecision decision(
      WhisperLoopVerdict verdict, {
      List<int> used = const [],
    }) => WhisperLoopDecision(
      loop: loop,
      verdict: verdict,
      secondaryIndices: List.unmodifiable(used),
      secondaryMatchingRows: heard,
      secondaryRowsInSpan: spanRows.length,
      secondaryLoops: secondaryLoops,
    );

    if (spanRows.isEmpty || secondaryLoops) return decision(noEvidence);
    // Qwen's rows are sentence-sized and Whisper's segment-sized, so the
    // counts are compared loosely: half the repeats is "about as often".
    if (heard >= 2 && heard * 2 >= loop.repeats) {
      return decision(WhisperLoopVerdict.keptAsSung);
    }
    if (!mayRemoveRows) return decision(WhisperLoopVerdict.flaggedOnly);
    return decision(WhisperLoopVerdict.replacedBySecondary, used: inSpan);
  }

  /// Every repeated row is a word or two and no row is implausibly dense:
  /// the shape of a sung chant rather than a decoder loop.
  static bool isChantLike(AsrSegmentLoop loop) =>
      loop.implausibleRateRows == 0 &&
      loop.unitKeys.every((key) => key.split(' ').toSet().length <= 2);

  /// How many times [rows] repeat the loop's block: for each row of the
  /// block, the larger of its exact occurrences in the rows' word stream and
  /// the rows that closely match it; the block repeats as often as its least
  /// repeated row.
  static int heardRepeats(AsrSegmentLoop loop, List<LyricLine> rows) {
    if (rows.isEmpty) return 0;
    final stream = <String>[
      for (final row in rows) ...AsrSegmentLoopDetector.tokens(row.text),
    ];
    final rowTokens = [
      for (final row in rows)
        AsrSegmentLoopDetector.loopKey(row.text).split(' ').toSet(),
    ];
    var least = -1;
    for (final key in loop.unitKeys) {
      final unit = key.split(' ');
      final exact = _occurrences(stream, unit);
      final unitSet = unit.toSet();
      final close = rowTokens
          .where((tokens) => _overlap(unitSet, tokens) >= matchingOverlap)
          .length;
      final count = exact > close ? exact : close;
      if (least < 0 || count < least) least = count;
    }
    return least < 0 ? 0 : least;
  }

  static int _occurrences(List<String> stream, List<String> unit) {
    if (unit.isEmpty || unit.length > stream.length) return 0;
    var count = 0;
    var index = 0;
    while (index + unit.length <= stream.length) {
      var matches = true;
      for (var offset = 0; offset < unit.length; offset++) {
        if (stream[index + offset] != unit[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        count++;
        index += unit.length;
      } else {
        index++;
      }
    }
    return count;
  }

  static bool _mostlyInside(LyricLine line, Duration start, Duration end) {
    final lineStart = line.startTime;
    final lineEnd = line.endTime > lineStart ? line.endTime : lineStart;
    final overlapStart = lineStart > start ? lineStart : start;
    final overlapEnd = lineEnd < end ? lineEnd : end;
    final length = (lineEnd - lineStart).inMilliseconds;
    if (length <= 0) return lineStart >= start && lineStart < end;
    final overlap = (overlapEnd - overlapStart).inMilliseconds;
    return overlap * 2 >= length;
  }

  static double _overlap(Set<String> unit, Set<String> row) {
    if (unit.isEmpty || row.isEmpty) return 0;
    final shared = unit.intersection(row).length;
    final larger = unit.length > row.length ? unit.length : row.length;
    return shared / larger;
  }

  static LyricLine _underReview(LyricLine line) => line.copyWith(
    confidence: line.confidence.clamp(0, reviewConfidenceCeiling).toInt(),
    // The ceiling is this policy's review signal, not the engine's score.
    confidenceSource: LyricConfidenceSource.heuristic,
  );
}
