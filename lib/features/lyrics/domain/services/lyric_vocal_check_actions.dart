import '../../../project/domain/models/lyric_document.dart';
import '../models/vocal_check_record.dart';
import 'lyric_indexed_review_metadata.dart';
import 'lyric_manual_edit_marker_service.dart';

/// The stretch of the song sent to a recogniser for one place where the
/// vocal check heard singing but the draft has no row (D-045), and where the
/// result goes.
class LyricVocalGapWindow {
  final LyricVocalCheckSpan span;

  /// On the document's timeline; [span] plus a little context, never
  /// reaching into the neighbouring rows.
  final Duration start;
  final Duration end;

  /// Row index the recognised rows are inserted at.
  final int insertAt;

  const LyricVocalGapWindow({
    required this.span,
    required this.start,
    required this.end,
    required this.insertAt,
  });

  Duration get length => end - start;

  /// The same stretch on the audio's timeline.
  ({Duration start, Duration end}) onAudio(Duration globalOffset) {
    var start = this.start + globalOffset;
    if (start.isNegative) start = Duration.zero;
    return (start: start, end: end + globalOffset);
  }
}

enum LyricVocalGapWindowFailure {
  /// Under half a second once squeezed between the neighbouring rows.
  tooShort,

  /// Longer than a recogniser should get in one go.
  tooLong,
}

class LyricVocalGapWindowResult {
  final LyricVocalGapWindow? window;
  final LyricVocalGapWindowFailure? failure;

  const LyricVocalGapWindowResult._(this.window, this.failure);

  bool get isUsable => window != null && failure == null;
}

/// Recognised rows that would go into a gap.
class LyricVocalGapInsertion {
  final LyricVocalGapWindow window;

  /// Clipped to the window, ordered and non-overlapping; no ids yet.
  final List<LyricLine> newLines;

  /// Recognised rows dropped for falling outside the window or being too
  /// short once clipped.
  final int clippedCount;

  const LyricVocalGapInsertion({
    required this.window,
    required this.newLines,
    required this.clippedCount,
  });

  bool get isEmpty => newLines.isEmpty;

  /// [document] with the rows inserted at [LyricVocalGapWindow.insertAt].
  /// Row-indexed review evidence of later rows moves with them; the new
  /// rows get ids. The vocal check record is left alone: the stretch closes
  /// because a row now covers it.
  LyricDocument applyTo(LyricDocument document) {
    if (newLines.isEmpty) return document;
    final at = window.insertAt.clamp(0, document.lines.length);
    final count = newLines.length;
    final inserted = document.copyWith(
      lines: [
        ...document.lines.sublist(0, at),
        ...newLines,
        ...document.lines.sublist(at),
      ],
      metadata: LyricIndexedReviewMetadata.remapped(
        document.metadata,
        (index) => index >= at ? index + count : index,
      ),
    );
    return const LyricManualEditMarkerService().assignMissingLineIds(inserted);
  }
}

/// Rows put back from the vocal check's removed list.
class LyricVocalRestore {
  final LyricDocument document;

  /// Indices of the restored rows in [document], ascending.
  final List<int> restoredIndices;

  /// Restored rows that overlap a row the document already had.
  final int overlapping;

  const LyricVocalRestore({
    required this.document,
    required this.restoredIndices,
    required this.overlapping,
  });

  int get count => restoredIndices.length;

  /// Ids of the restored rows: the user chose to keep them, so the editor
  /// protects them like hand edits.
  Set<String> get restoredIds => {
    for (final index in restoredIndices) ?document.lines[index].id,
  };
}

/// Plans the follow-ups of the vocal check (D-044) the editor offers with
/// one click (D-045): recognising a stretch of singing that has no row,
/// saying a stretch has no lyrics, and putting removed rows back.
///
/// Every result is a new document for one undoable change; nothing here
/// talks to a recogniser or the disk.
class LyricVocalCheckActions {
  const LyricVocalCheckActions();

  /// Context on each side of a stretch, so a recogniser does not start or
  /// stop mid-word.
  static const Duration context = Duration(milliseconds: 300);
  static const Duration minWindow = Duration(milliseconds: 500);
  static const Duration maxWindow = Duration(seconds: 90);

  /// Shorter recognised rows (after clipping) are fragments.
  static const Duration minRowLength = Duration(milliseconds: 120);

  /// The stretch to recognise for [span]: [context] on each side, but never
  /// into the neighbouring rows (unless the span itself already overlaps
  /// them) and never past [audioDuration].
  LyricVocalGapWindowResult window(
    LyricDocument document,
    LyricVocalCheckSpan span, {
    Duration? audioDuration,
  }) {
    final lines = document.lines;
    final at = insertionIndex(document, span.start);

    var floor = Duration.zero;
    for (var index = 0; index < at; index++) {
      final end = lines[index].endTime;
      if (end > floor) floor = end;
    }
    if (floor > span.start) floor = span.start;
    Duration? ceiling;
    for (var index = at; index < lines.length; index++) {
      final start = lines[index].startTime;
      if (ceiling == null || start < ceiling) ceiling = start;
    }
    if (ceiling != null && ceiling < span.end) ceiling = span.end;
    if (audioDuration != null && (ceiling == null || ceiling > audioDuration)) {
      ceiling = audioDuration > span.start ? audioDuration : span.end;
    }

    var start = span.start - context;
    if (start < floor) start = floor;
    if (start.isNegative) start = Duration.zero;
    var end = span.end + context;
    if (ceiling != null && end > ceiling) end = ceiling;

    final window = LyricVocalGapWindow(
      span: span,
      start: start,
      end: end,
      insertAt: at,
    );
    if (window.length < minWindow) {
      return LyricVocalGapWindowResult._(
        window,
        LyricVocalGapWindowFailure.tooShort,
      );
    }
    if (window.length > maxWindow) {
      return LyricVocalGapWindowResult._(
        window,
        LyricVocalGapWindowFailure.tooLong,
      );
    }
    return LyricVocalGapWindowResult._(window, null);
  }

  /// Where a row starting at [start] belongs: before the first row that
  /// starts later, so rows starting at the same time keep their order.
  int insertionIndex(LyricDocument document, Duration start) {
    final lines = document.lines;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].startTime > start) return index;
    }
    return lines.length;
  }

  /// [recognized] must already be on the document's timeline.
  LyricVocalGapInsertion insertion(
    LyricVocalGapWindow window, {
    required List<LyricLine> recognized,
  }) {
    final sorted = [...recognized]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final newLines = <LyricLine>[];
    var clipped = 0;
    for (final line in sorted) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      var start = line.startTime < window.start ? window.start : line.startTime;
      final end = line.endTime > window.end ? window.end : line.endTime;
      if (newLines.isNotEmpty && start < newLines.last.endTime) {
        start = newLines.last.endTime;
      }
      if (end - start < minRowLength) {
        clipped++;
        continue;
      }
      newLines.add(
        LyricLine(
          text: text,
          startTime: start,
          endTime: end,
          confidence: line.confidence,
          confidenceSource: line.confidenceSource,
          words: _clipWords(line.words, start, end),
        ),
      );
    }
    return LyricVocalGapInsertion(
      window: window,
      newLines: List.unmodifiable(newLines),
      clippedCount: clipped,
    );
  }

  /// [document] with [span] taken off the vocal check's list of stretches
  /// without lyrics; unchanged when there is no record or it does not list
  /// the span.
  LyricDocument dismiss(LyricDocument document, LyricVocalCheckSpan span) {
    final record = LyricVocalCheckRecord.fromMetadata(document.metadata);
    if (record == null || !record.uncoveredSpans.contains(span)) {
      return document;
    }
    return document.copyWith(
      metadata: record.withDismissed(span).writeTo(document.metadata),
    );
  }

  /// [document] with the removed rows at [selection] (positions in
  /// [LyricVocalCheckRecord.removedLines]) back at their recognised times,
  /// each placed by its start time. The record no longer lists them. Null
  /// when there is no record or nothing in [selection] is listed.
  LyricVocalRestore? restore(LyricDocument document, Set<int> selection) {
    final record = LyricVocalCheckRecord.fromMetadata(document.metadata);
    if (record == null) return null;
    final chosen = [
      for (var index = 0; index < record.removedLines.length; index++)
        if (selection.contains(index)) index,
    ];
    if (chosen.isEmpty) return null;

    final original = document.lines;
    var overlapping = 0;
    var lines = [...original];
    var metadata = document.metadata;
    final restored = <int>[];
    final pending = [for (final index in chosen) record.removedLines[index]]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final removed in pending) {
      if (original.any(
        (line) => line.startTime < removed.end && line.endTime > removed.start,
      )) {
        overlapping++;
      }
      var at = lines.length;
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].startTime > removed.start) {
          at = index;
          break;
        }
      }
      lines = [...lines.sublist(0, at), removed.toLine(), ...lines.sublist(at)];
      metadata = LyricIndexedReviewMetadata.afterRowInserted(metadata, at);
      for (var index = 0; index < restored.length; index++) {
        if (restored[index] >= at) restored[index]++;
      }
      restored.add(at);
    }
    restored.sort();
    final withIds = const LyricManualEditMarkerService().assignMissingLineIds(
      document.copyWith(
        lines: lines,
        metadata: record.withRestored(chosen.toSet()).writeTo(metadata),
      ),
    );
    return LyricVocalRestore(
      document: withIds,
      restoredIndices: List.unmodifiable(restored),
      overlapping: overlapping,
    );
  }

  /// Every removed row back; null when there is none.
  LyricVocalRestore? restoreAll(LyricDocument document) {
    final record = LyricVocalCheckRecord.fromMetadata(document.metadata);
    if (record == null || record.removedLines.isEmpty) return null;
    return restore(document, {
      for (var index = 0; index < record.removedLines.length; index++) index,
    });
  }

  static List<LyricWordTiming> _clipWords(
    List<LyricWordTiming> words,
    Duration start,
    Duration end,
  ) {
    final clipped = <LyricWordTiming>[];
    for (final word in words) {
      if (word.end < start || word.start > end) continue;
      clipped.add(
        LyricWordTiming(
          text: word.text,
          start: word.start < start ? start : word.start,
          end: word.end > end ? end : word.end,
        ),
      );
    }
    // Word timing that lost words no longer covers the row's text.
    if (clipped.length != words.length) return const [];
    return List.unmodifiable(clipped);
  }
}
