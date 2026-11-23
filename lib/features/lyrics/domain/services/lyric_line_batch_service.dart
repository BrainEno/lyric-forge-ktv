import '../../../project/domain/models/lyric_document.dart';
import 'lyric_indexed_review_metadata.dart';
import 'lyric_line_structure_service.dart';
import 'lyric_timeline_validator.dart';
import 'lyric_timing_shift_service.dart';

/// The outcome of [LyricLineBatchService.shift].
class LyricBatchShiftResult {
  const LyricBatchShiftResult({
    required this.document,
    required this.changedCount,
    required this.clampedCount,
    required this.introducedIssues,
  });

  /// Null when the shift changes nothing.
  final LyricDocument? document;

  /// Rows whose start or end moved.
  final int changedCount;

  /// Rows held at 0:00 or at the end of the audio.
  final int clampedCount;

  /// Timeline problems the shift creates, such as a moved row now
  /// overlapping a neighbour it did not overlap before.
  final List<TimelineIssue> introducedIssues;

  bool get isSuccess => document != null;
}

/// Edits several chosen rows at once (D-066): delete, merge, move in time.
///
/// The rows need not be next to each other, except for a merge. Each
/// function works on the row indices of [LyricDocument.lines] and keeps the
/// row-indexed review evidence (`fallbackCandidates`, suggested insertions)
/// attached to the rows that remain, like the single-row edits do.
class LyricLineBatchService {
  const LyricLineBatchService({
    this.structure = const LyricLineStructureService(),
    this.timing = const LyricTimingShiftService(),
    this.validator = const LyricTimelineValidator(),
  });

  final LyricLineStructureService structure;
  final LyricTimingShiftService timing;
  final LyricTimelineValidator validator;

  /// The valid rows of [indices] for [document], ascending, without repeats.
  static List<int> normalize(LyricDocument document, Iterable<int> indices) {
    final rows = {
      for (final index in indices)
        if (index >= 0 && index < document.lines.length) index,
    }.toList()..sort();
    return rows;
  }

  /// Whether the ascending [rows] follow each other with no gap.
  static bool isContiguous(List<int> rows) {
    for (var position = 1; position < rows.length; position++) {
      if (rows[position] != rows[position - 1] + 1) return false;
    }
    return true;
  }

  /// The ascending [rows] cut into runs of consecutive rows.
  static List<List<int>> runs(List<int> rows) {
    final result = <List<int>>[];
    for (final row in rows) {
      if (result.isNotEmpty && result.last.last + 1 == row) {
        result.last.add(row);
      } else {
        result.add([row]);
      }
    }
    return result;
  }

  /// [document] without the rows in [indices].
  LyricDocument delete(LyricDocument document, Iterable<int> indices) {
    final rows = normalize(document, indices);
    if (rows.isEmpty) return document;
    final lines = List<LyricLine>.from(document.lines);
    var metadata = document.metadata;
    // From the bottom up, so each removal leaves the next index valid.
    for (final row in rows.reversed) {
      lines.removeAt(row);
      metadata = LyricIndexedReviewMetadata.afterRowRemoved(metadata, row);
    }
    return document.copyWith(lines: lines, metadata: metadata);
  }

  /// [document] with the consecutive rows in [indices] joined into one row
  /// at the first of them, or null unless they are two or more consecutive
  /// rows. The joined row keeps the first row's id.
  LyricDocument? merge(LyricDocument document, Iterable<int> indices) {
    final rows = normalize(document, indices);
    if (rows.length < 2 || !isContiguous(rows)) return null;
    final first = rows.first;
    var merged = document.lines[first];
    var metadata = document.metadata;
    for (final row in rows.skip(1)) {
      merged = structure.merge(merged, document.lines[row]);
      metadata = LyricIndexedReviewMetadata.afterRowsMerged(metadata, first);
    }
    final lines = List<LyricLine>.from(document.lines)
      ..replaceRange(first, rows.last + 1, [merged]);
    return document.copyWith(lines: lines, metadata: metadata);
  }

  /// Moves the start and end of every row in [indices] by [delta].
  ///
  /// Rows that would start before 0:00 or end after [audioDuration] are held
  /// at that edge, as in the range tool (`LyricTimingShiftService`), which
  /// does the moving one run of consecutive rows at a time.
  LyricBatchShiftResult shift(
    LyricDocument document,
    Iterable<int> indices,
    Duration delta, {
    Duration? audioDuration,
  }) {
    const nothing = LyricBatchShiftResult(
      document: null,
      changedCount: 0,
      clampedCount: 0,
      introducedIssues: [],
    );
    final rows = normalize(document, indices);
    if (rows.isEmpty || delta == Duration.zero) return nothing;
    var current = document;
    var changed = 0;
    var clamped = 0;
    for (final run in runs(rows)) {
      final result = timing.apply(
        current,
        LyricTimingShift.offset(
          firstIndex: run.first,
          lastIndex: run.last,
          delta: delta,
        ),
        audioDuration: audioDuration,
      );
      final next = result.document;
      if (next == null) continue;
      current = next;
      changed += result.changedIndices.length;
      clamped += result.clampedCount;
    }
    if (changed == 0) return nothing;
    final comparison = validator.compare(
      before: document.lines,
      after: current.lines,
      audioDuration: audioDuration,
      globalOffset: document.globalOffset ?? Duration.zero,
    );
    return LyricBatchShiftResult(
      document: current,
      changedCount: changed,
      clampedCount: clamped,
      introducedIssues: comparison.introduced,
    );
  }
}
