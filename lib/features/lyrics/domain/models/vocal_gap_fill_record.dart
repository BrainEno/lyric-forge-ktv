import '../../../project/domain/models/lyric_document.dart';
import 'vocal_check_record.dart';

/// Rows whole-song recognition inserted on its own, as its optional last
/// step (D-047), into stretches where the vocal check (D-044) heard singing
/// but the draft had no row.
///
/// Nobody has listened to these rows yet and only one recogniser produced
/// each of them, so the editor puts them in the review queue until a person
/// confirms them. They are found by row id, which survives inserting,
/// deleting and re-timing other rows; a row that is deleted simply drops out.
///
/// The record lives in `LyricDocument.metadata[metadataKey]`.
class LyricVocalGapFillRecord {
  static const String metadataKey = 'vocalGapFill';
  static const int schemaVersion = 1;

  /// Ids of the inserted rows, in timeline order.
  final List<String> insertedLineIds;

  /// The vocal check's stretches that got at least one row.
  final List<LyricVocalCheckSpan> filledSpans;

  /// Stretches both recognisers heard no words in.
  final int emptySpans;

  /// Stretches whose recognition failed with every engine.
  final int failedSpans;

  /// Stretches that were not sent: too short or too long for a window, past
  /// the step's budget, or after the step stopped early.
  final int unattemptedSpans;

  /// Of [filledSpans], how many only the second engine filled.
  final int fallbackSpans;

  const LyricVocalGapFillRecord({
    this.insertedLineIds = const [],
    this.filledSpans = const [],
    this.emptySpans = 0,
    this.failedSpans = 0,
    this.unattemptedSpans = 0,
    this.fallbackSpans = 0,
  });

  bool get isEmpty => insertedLineIds.isEmpty;

  /// Stretches the step looked at, whatever came of them.
  int get totalSpans =>
      filledSpans.length + emptySpans + failedSpans + unattemptedSpans;

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'insertedLineIds': List<String>.of(insertedLineIds),
    'filledSpans': [for (final span in filledSpans) span.toJson()],
    'emptySpans': emptySpans,
    'failedSpans': failedSpans,
    'unattemptedSpans': unattemptedSpans,
    'fallbackSpans': fallbackSpans,
  };

  /// [metadata] with this record stored, as a new map.
  Map<String, dynamic> writeTo(Map<String, dynamic> metadata) => {
    ...metadata,
    metadataKey: toJson(),
  };

  /// The record in [metadata]; null when absent, from a newer schema, or
  /// malformed. Malformed entries inside a valid record are skipped.
  static LyricVocalGapFillRecord? fromMetadata(Map<String, dynamic> metadata) {
    final raw = metadata[metadataKey];
    if (raw is! Map || raw['schemaVersion'] != schemaVersion) return null;
    final ids = raw['insertedLineIds'];
    final spans = raw['filledSpans'];
    int count(Object? value) => value is int && value > 0 ? value : 0;
    return LyricVocalGapFillRecord(
      insertedLineIds: [
        if (ids is List)
          for (final id in ids)
            if (id is String && id.isNotEmpty) id,
      ],
      filledSpans: [
        if (spans is List)
          for (final entry in spans) ?LyricVocalCheckSpan.tryFromJson(entry),
      ],
      emptySpans: count(raw['emptySpans']),
      failedSpans: count(raw['failedSpans']),
      unattemptedSpans: count(raw['unattemptedSpans']),
      fallbackSpans: count(raw['fallbackSpans']),
    );
  }

  /// Indices of the rows of [document] this step inserted that are still
  /// there and still have text, ascending.
  List<int> insertedIndices(LyricDocument document) {
    if (insertedLineIds.isEmpty) return const [];
    final ids = insertedLineIds.toSet();
    return [
      for (final (index, line) in document.lines.indexed)
        if (line.id != null &&
            ids.contains(line.id) &&
            line.text.trim().isNotEmpty)
          index,
    ];
  }
}
