import '../../../project/domain/models/lyric_document.dart';

/// A stretch of the song's timeline.
class LyricVocalCheckSpan {
  final Duration start;
  final Duration end;

  const LyricVocalCheckSpan(this.start, this.end);

  Duration get duration => end - start;

  List<int> toJson() => [start.inMilliseconds, end.inMilliseconds];

  /// Null for anything but `[startMs, endMs]` with `0 <= start < end`.
  static LyricVocalCheckSpan? tryFromJson(Object? json) {
    if (json is! List || json.length != 2) return null;
    final start = json[0];
    final end = json[1];
    if (start is! int || end is! int || start < 0 || end <= start) {
      return null;
    }
    return LyricVocalCheckSpan(
      Duration(milliseconds: start),
      Duration(milliseconds: end),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricVocalCheckSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'LyricVocalCheckSpan(${start.inMilliseconds}–${end.inMilliseconds} ms)';
}

/// A row the vocal check deleted because nobody sings during it.
class LyricVocalCheckRemovedLine {
  final String text;
  final Duration start;
  final Duration end;

  const LyricVocalCheckRemovedLine({
    required this.text,
    required this.start,
    required this.end,
  });

  Map<String, Object> toJson() => {
    'text': text,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };

  /// The row as it goes back into the document; it gets a new id.
  LyricLine toLine() => LyricLine(text: text, startTime: start, endTime: end);

  static LyricVocalCheckRemovedLine? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final start = json['startMs'];
    final end = json['endMs'];
    if (text is! String || start is! int || end is! int || start < 0) {
      return null;
    }
    if (end < start) return null;
    return LyricVocalCheckRemovedLine(
      text: text,
      start: Duration(milliseconds: start),
      end: Duration(milliseconds: end),
    );
  }
}

/// What the vocal check (D-044) did to a freshly recognised draft.
///
/// Recognition of a separated vocal stem is followed by a look at the stem
/// itself: rows during which nobody sings are recognisers inventing lyrics in
/// an intro, interlude or outro and are deleted; row boundaries that reach
/// into silence are pulled in to where the singing starts and stops; and
/// stretches of singing that no row covers are kept as places where lyrics
/// were probably missed.
///
/// The record lives in `LyricDocument.metadata[metadataKey]` so the editor
/// can say what happened and where to listen. It describes the audio and
/// the draft as recognised; [openSpans] re-checks the missed stretches
/// against the rows the document has now.
class LyricVocalCheckRecord {
  static const String metadataKey = 'vocalCheck';
  static const int schemaVersion = 1;

  /// Rows deleted for having no singing, in timeline order.
  final List<LyricVocalCheckRemovedLine> removedLines;

  /// Rows whose start or end was moved onto the singing.
  final int retimedLines;

  /// Stretches with singing but no row, in timeline order.
  final List<LyricVocalCheckSpan> uncoveredSpans;

  /// Removed rows the user put back since (D-045); they are no longer in
  /// [removedLines].
  final int restoredLines;

  /// Stretches the user said have no lyrics (humming, a sample, separation
  /// leftovers); they are no longer in [uncoveredSpans].
  final int dismissedSpans;

  const LyricVocalCheckRecord({
    this.removedLines = const [],
    this.retimedLines = 0,
    this.uncoveredSpans = const [],
    this.restoredLines = 0,
    this.dismissedSpans = 0,
  });

  bool get changedDraft => removedLines.isNotEmpty || retimedLines > 0;

  bool get isEmpty => !changedDraft && uncoveredSpans.isEmpty;

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'removedLines': [for (final line in removedLines) line.toJson()],
    'retimedLines': retimedLines,
    'uncoveredSpans': [for (final span in uncoveredSpans) span.toJson()],
    if (restoredLines > 0) 'restoredLines': restoredLines,
    if (dismissedSpans > 0) 'dismissedSpans': dismissedSpans,
  };

  /// The record without the removed rows at [indices] (positions in
  /// [removedLines]), counted as restored. Unknown positions are ignored.
  LyricVocalCheckRecord withRestored(Set<int> indices) {
    final kept = <LyricVocalCheckRemovedLine>[];
    var restored = 0;
    for (var index = 0; index < removedLines.length; index++) {
      if (indices.contains(index)) {
        restored++;
      } else {
        kept.add(removedLines[index]);
      }
    }
    return LyricVocalCheckRecord(
      removedLines: kept,
      retimedLines: retimedLines,
      uncoveredSpans: uncoveredSpans,
      restoredLines: restoredLines + restored,
      dismissedSpans: dismissedSpans,
    );
  }

  /// The record without [span], counted as dismissed; unchanged when the
  /// record does not list it.
  LyricVocalCheckRecord withDismissed(LyricVocalCheckSpan span) {
    if (!uncoveredSpans.contains(span)) return this;
    return LyricVocalCheckRecord(
      removedLines: removedLines,
      retimedLines: retimedLines,
      uncoveredSpans: [
        for (final other in uncoveredSpans)
          if (other != span) other,
      ],
      restoredLines: restoredLines,
      dismissedSpans: dismissedSpans + 1,
    );
  }

  /// [metadata] with this record stored, as a new map.
  Map<String, dynamic> writeTo(Map<String, dynamic> metadata) => {
    ...metadata,
    metadataKey: toJson(),
  };

  /// The record in [metadata]; null when absent, from a newer schema, or
  /// malformed. Malformed entries inside a valid record are skipped.
  static LyricVocalCheckRecord? fromMetadata(Map<String, dynamic> metadata) {
    final raw = metadata[metadataKey];
    if (raw is! Map || raw['schemaVersion'] != schemaVersion) return null;
    final removed = raw['removedLines'];
    final spans = raw['uncoveredSpans'];
    final retimed = raw['retimedLines'];
    final restored = raw['restoredLines'];
    final dismissed = raw['dismissedSpans'];
    return LyricVocalCheckRecord(
      removedLines: [
        if (removed is List)
          for (final entry in removed)
            ?LyricVocalCheckRemovedLine.tryFromJson(entry),
      ],
      retimedLines: retimed is int && retimed > 0 ? retimed : 0,
      uncoveredSpans: [
        if (spans is List)
          for (final entry in spans) ?LyricVocalCheckSpan.tryFromJson(entry),
      ],
      restoredLines: restored is int && restored > 0 ? restored : 0,
      dismissedSpans: dismissed is int && dismissed > 0 ? dismissed : 0,
    );
  }

  /// The [uncoveredSpans] that still have no row in [document]: a row added
  /// since (typed, inserted or re-recognised) that overlaps a stretch, give
  /// or take [tolerance], closes it.
  List<LyricVocalCheckSpan> openSpans(
    LyricDocument document, {
    Duration tolerance = const Duration(milliseconds: 300),
  }) {
    if (uncoveredSpans.isEmpty) return const [];
    final rows = [
      for (final line in document.lines)
        if (line.text.trim().isNotEmpty && line.endTime > line.startTime) line,
    ];
    return [
      for (final span in uncoveredSpans)
        if (!rows.any(
          (line) =>
              line.startTime - tolerance < span.end &&
              line.endTime + tolerance > span.start,
        ))
          span,
    ];
  }
}
