import '../../../project/domain/models/lyric_document.dart';
import '../models/vocal_check_record.dart';
import 'lyric_indexed_review_metadata.dart';
import 'lyric_manual_edit_marker_service.dart';
import 'lyric_span_rerecognition.dart';
import 'lyric_vocal_check_actions.dart';

/// One stretch of a batch: the window it is recognised in, or why it is not
/// sent (D-046).
class LyricVocalGapBatchItem {
  final LyricVocalCheckSpan span;

  /// Null only when the stretch could not be placed at all.
  final LyricVocalGapWindow? window;
  final LyricVocalGapWindowFailure? failure;

  const LyricVocalGapBatchItem({
    required this.span,
    required this.window,
    required this.failure,
  });

  bool get isSendable => window != null && failure == null;
}

/// Every open stretch of a document, in timeline order.
class LyricVocalGapBatchPlan {
  final List<LyricVocalGapBatchItem> items;

  const LyricVocalGapBatchPlan(this.items);

  int get sendableCount => items.where((item) => item.isSendable).length;
  int get skippedCount => items.length - sendableCount;
  bool get isEmpty => items.isEmpty;
}

/// The engine to try when the first one heard nothing: the other one.
LyricSpanEngine lyricOtherSpanEngine(LyricSpanEngine engine) =>
    switch (engine) {
      LyricSpanEngine.qwen => LyricSpanEngine.whisper,
      LyricSpanEngine.whisper => LyricSpanEngine.qwen,
    };

/// The document after a batch, and what changed.
class LyricVocalGapBatchResult {
  final LyricDocument document;

  /// Indices of the inserted rows in [document], ascending.
  final List<int> insertedIndices;

  /// Stretches that got at least one row.
  final int filledGaps;

  /// Stretches taken off the record as having no lyrics.
  final int dismissedGaps;

  const LyricVocalGapBatchResult({
    required this.document,
    required this.insertedIndices,
    required this.filledGaps,
    required this.dismissedGaps,
  });

  int get insertedCount => insertedIndices.length;
}

/// Recognising every stretch of singing without lyrics at once (D-046):
/// plans one window per stretch with [LyricVocalCheckActions.window], and
/// applies the accepted insertions — each planned against the same
/// document — as one edit.
///
/// Nothing here talks to a recogniser.
class LyricVocalGapBatch {
  const LyricVocalGapBatch({this.actions = const LyricVocalCheckActions()});

  final LyricVocalCheckActions actions;

  /// Recognised rows shorter than this after making a batch's rows
  /// consecutive are dropped, as for one stretch.
  static Duration get minRowLength => LyricVocalCheckActions.minRowLength;

  LyricVocalGapBatchPlan plan(
    LyricDocument document,
    List<LyricVocalCheckSpan> spans, {
    Duration? audioDuration,
  }) {
    final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
    return LyricVocalGapBatchPlan(
      List.unmodifiable([
        for (final span in sorted)
          _item(
            span,
            actions.window(document, span, audioDuration: audioDuration),
          ),
      ]),
    );
  }

  static LyricVocalGapBatchItem _item(
    LyricVocalCheckSpan span,
    LyricVocalGapWindowResult result,
  ) => LyricVocalGapBatchItem(
    span: span,
    window: result.window,
    failure: result.failure,
  );

  /// [document] with every non-empty insertion in [insertions] applied and
  /// every stretch in [dismiss] taken off the vocal check record. All
  /// insertions must have been planned against [document]; rows of
  /// different stretches that end up between the same two rows are made
  /// consecutive. Row-indexed review evidence moves with the old rows; the
  /// new rows get ids. Null when nothing would change.
  LyricVocalGapBatchResult? apply(
    LyricDocument document, {
    required List<LyricVocalGapInsertion> insertions,
    Iterable<LyricVocalCheckSpan> dismiss = const [],
  }) {
    final original = document.lines;
    int at(LyricVocalGapInsertion insertion) =>
        insertion.window.insertAt.clamp(0, original.length);
    final pending = [
      for (final insertion in insertions)
        if (!insertion.isEmpty) insertion,
    ]..sort((a, b) {
        final byIndex = at(a).compareTo(at(b));
        return byIndex != 0
            ? byIndex
            : a.window.start.compareTo(b.window.start);
      });

    final lines = <LyricLine>[];
    final inserted = <int>[];
    final newIndexOf = List<int>.filled(original.length, 0);
    var filled = 0;
    var next = 0;
    for (var index = 0; index <= original.length; index++) {
      Duration? groupEnd;
      while (next < pending.length && at(pending[next]) == index) {
        var added = false;
        for (final line in pending[next].newLines) {
          var row = line;
          if (groupEnd != null && row.startTime < groupEnd) {
            if (row.endTime - groupEnd < minRowLength) continue;
            row = row.copyWith(startTime: groupEnd);
          }
          inserted.add(lines.length);
          lines.add(row);
          groupEnd = row.endTime;
          added = true;
        }
        if (added) filled++;
        next++;
      }
      if (index < original.length) {
        newIndexOf[index] = lines.length;
        lines.add(original[index]);
      }
    }

    var metadata = document.metadata;
    var dismissed = 0;
    final record = LyricVocalCheckRecord.fromMetadata(metadata);
    if (record != null) {
      var updated = record;
      for (final span in dismiss) {
        final after = updated.withDismissed(span);
        if (!identical(after, updated)) dismissed++;
        updated = after;
      }
      if (dismissed > 0) metadata = updated.writeTo(metadata);
    }
    if (inserted.isEmpty && dismissed == 0) return null;

    if (inserted.isNotEmpty) {
      metadata = LyricIndexedReviewMetadata.remapped(
        metadata,
        (index) => index < newIndexOf.length ? newIndexOf[index] : null,
      );
    }
    final changed = const LyricManualEditMarkerService().assignMissingLineIds(
      document.copyWith(lines: lines, metadata: metadata),
    );
    return LyricVocalGapBatchResult(
      document: changed,
      insertedIndices: List.unmodifiable(inserted),
      filledGaps: filled,
      dismissedGaps: dismissed,
    );
  }
}
