import '../../../project/domain/models/lyric_document.dart';
import 'asr_segment_loop_detector.dart';

/// A stretch of audio whose Whisper output looped and is decoded again with
/// the rolling text history switched off.
class WhisperLoopRegion {
  /// Loops (by first segment index in the first-pass output) this region
  /// covers.
  final List<AsrSegmentLoop> loops;

  final Duration start;
  final Duration end;

  const WhisperLoopRegion({
    required this.loops,
    required this.start,
    required this.end,
  });

  Duration get duration => end - start;

  /// Looped first-pass segments the region covers.
  int get loopedRowCount =>
      loops.fold(0, (total, loop) => total + loop.rowCount);

  /// First-pass segment indices the region replaces when the re-decode is
  /// accepted: every row from the first loop to the last (rows between two
  /// merged loops are decoded again too) and every other row that starts
  /// inside the region, because the re-decode covers that audio as well.
  Set<int> replacedIndicesIn(List<LyricLine> lines) {
    final firstLooped = loops.first.leadInIndex;
    final endLooped = loops.last.endIndex;
    return {
      for (
        var index = firstLooped;
        index < endLooped && index < lines.length;
        index++
      )
        index,
      for (var index = 0; index < lines.length; index++)
        if (lines[index].startTime >= start && lines[index].startTime < end)
          index,
    };
  }

  Map<String, dynamic> toMetadata() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'loops': [for (final loop in loops) loop.toMetadata()],
  };
}

/// What happened to one region.
enum WhisperLoopRegionOutcome {
  /// The history-free decode had no loop and replaced the looped rows.
  replaced,

  /// The history-free decode looped as well (or produced nothing usable);
  /// the first-pass rows stay and the fusion step must judge them.
  stillLooping,

  /// The history-free decode produced no row inside the region.
  empty,

  /// The re-decode could not run (runtime lacks the flags, process failed).
  failed,
}

/// The splice result for one region.
class WhisperLoopSplice {
  final WhisperLoopRegionOutcome outcome;
  final List<LyricLine> lines;
  final int insertedCount;

  const WhisperLoopSplice({
    required this.outcome,
    required this.lines,
    required this.insertedCount,
  });
}

/// Plans and applies the history-free re-decode of looped Whisper spans.
///
/// The loop is caused by whisper.cpp conditioning each window on its own
/// earlier output, so the targeted cure is to decode the same audio again
/// with that conditioning off (`--max-context 0`). The lyrics profile already
/// decodes the whole song that way (D-027); this policy covers runs that kept
/// the history — the standard profile, or a lyrics run on a runtime that
/// rejected the flag — and only the stretches that actually looped are
/// decoded again. The re-decode is itself checked: if it still loops, the
/// repetition is probably sung and the first-pass rows are kept for the
/// fusion step to compare with Qwen.
class WhisperLoopRecoveryPolicy {
  /// Stable identifier written to metadata and the checkpoint fingerprint.
  /// Bump it whenever detection thresholds or the splice rules change.
  static const String id = 'whisper-loop-redecode-v1';

  /// Regions decoded again per song, so a pathological file cannot multiply
  /// the recognition time.
  static const int maxRegions = 3;

  /// Loops closer than this share one re-decode.
  static const Duration mergeGap = Duration(seconds: 4);

  /// Shortest audio handed to the re-decode. Whisper needs some context to
  /// settle on a language and phrasing; a 3 s clip is mostly guesswork.
  static const Duration minRegion = Duration(seconds: 8);

  /// Longest single re-decode.
  static const Duration maxRegion = Duration(minutes: 4);

  final AsrSegmentLoopDetector detector;

  const WhisperLoopRecoveryPolicy({
    this.detector = const AsrSegmentLoopDetector(),
  });

  /// Regions worth decoding again: only strong loops, since a weak one (three
  /// identical rows) is common in real choruses and the fusion step can weigh
  /// it against Qwen without another Whisper run.
  List<WhisperLoopRegion> plan(
    List<LyricLine> lines, {
    Duration? audioDuration,
  }) {
    final strong = [
      for (final loop in detector.detect(lines))
        if (loop.strong) loop,
    ];
    if (strong.isEmpty) return const [];

    final regions = <WhisperLoopRegion>[];
    for (final loop in strong) {
      if (regions.isNotEmpty &&
          loop.spanStart - regions.last.end <= mergeGap) {
        final previous = regions.removeLast();
        regions.add(
          WhisperLoopRegion(
            loops: [...previous.loops, loop],
            start: previous.start,
            end: loop.end > previous.end ? loop.end : previous.end,
          ),
        );
      } else {
        regions.add(
          WhisperLoopRegion(
            loops: [loop],
            start: loop.spanStart,
            end: loop.end,
          ),
        );
      }
    }

    final bounded = <WhisperLoopRegion>[];
    for (final region in regions) {
      var end = region.end;
      if (end - region.start < minRegion) end = region.start + minRegion;
      if (audioDuration != null && end > audioDuration) end = audioDuration;
      if (end - region.start > maxRegion) end = region.start + maxRegion;
      if (end <= region.start) continue;
      bounded.add(
        WhisperLoopRegion(loops: region.loops, start: region.start, end: end),
      );
    }
    // The largest loops first: they are the ones users see.
    bounded.sort((a, b) => b.loopedRowCount.compareTo(a.loopedRowCount));
    final kept = bounded.take(maxRegions).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(kept);
  }

  /// Replaces the region's looped rows in [lines] with the [redecoded] rows
  /// that fall inside it, unless the re-decode loops too.
  ///
  /// [redecoded] timestamps must be absolute (whisper-cli's `--offset-t`
  /// keeps them on the file's timeline). Rows are clipped so they cannot run
  /// into the first-pass row that follows the region.
  WhisperLoopSplice splice({
    required List<LyricLine> lines,
    required WhisperLoopRegion region,
    required List<LyricLine> redecoded,
  }) {
    const startTolerance = Duration(milliseconds: 300);
    final replaced = region.replacedIndicesIn(lines);
    final inside = <LyricLine>[];
    for (final line in redecoded) {
      if (line.text.trim().isEmpty) continue;
      if (line.startTime < region.start - startTolerance) continue;
      if (line.startTime >= region.end) continue;
      final start = line.startTime < region.start
          ? region.start
          : line.startTime;
      var end = line.endTime > region.end ? region.end : line.endTime;
      if (end <= start) end = start + const Duration(milliseconds: 1);
      inside.add(line.copyWith(startTime: start, endTime: end));
    }
    if (inside.isEmpty) {
      return WhisperLoopSplice(
        outcome: WhisperLoopRegionOutcome.empty,
        lines: lines,
        insertedCount: 0,
      );
    }
    if (detector.detect(inside).any((loop) => loop.strong)) {
      return WhisperLoopSplice(
        outcome: WhisperLoopRegionOutcome.stillLooping,
        lines: lines,
        insertedCount: 0,
      );
    }

    // Kept rows start either before the region or at/after its end, so the
    // timeline stays ordered without re-sorting (Dart's sort is not stable).
    final result = <LyricLine>[
      for (var index = 0; index < lines.length; index++)
        if (!replaced.contains(index) && lines[index].startTime < region.start)
          lines[index],
      ...inside,
      for (var index = 0; index < lines.length; index++)
        if (!replaced.contains(index) &&
            lines[index].startTime >= region.start)
          lines[index],
    ];
    return WhisperLoopSplice(
      outcome: WhisperLoopRegionOutcome.replaced,
      lines: List.unmodifiable(result),
      insertedCount: inside.length,
    );
  }
}
