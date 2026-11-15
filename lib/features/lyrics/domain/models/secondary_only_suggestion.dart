import '../../../project/domain/models/lyric_document.dart';

/// A lyric row that only the secondary recogniser heard.
///
/// Dual-engine fusion never drops such a row and never treats it as confirmed:
/// it is inserted on the time axis with a capped review confidence, and this
/// record says so. The editor shows it as "建议补入" until the user keeps it
/// (review decision), rewrites it, or deletes it.
///
/// Records are matched to rows by exact text and raw timestamps instead of by
/// row index. Inserting or deleting other rows therefore cannot re-attach a
/// suggestion to the wrong line, and once the user edits the row's text or
/// timing it is the user's line, no longer an engine suggestion.
class SecondaryOnlySuggestion {
  static const String metadataKey = 'secondaryOnlySuggestions';
  static const int version = 1;

  /// Why the row was kept. Stable codes for diagnostics and tests.
  static const String reasonNoPrimaryCounterpart = 'no_primary_counterpart';

  final String text;
  final int startMs;
  final int endMs;

  /// Engine identity of the recogniser that produced the row, when known.
  final String? engine;

  /// The engine's own score before fusion capped it for review. Null when the
  /// engine did not report one.
  final int? engineConfidence;
  final String reason;

  const SecondaryOnlySuggestion({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.engine,
    this.engineConfidence,
    this.reason = reasonNoPrimaryCounterpart,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'startMs': startMs,
    'endMs': endMs,
    'engine': ?engine,
    'engineConfidence': ?engineConfidence,
    'reason': reason,
  };

  static SecondaryOnlySuggestion? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final startMs = raw['startMs'];
    final endMs = raw['endMs'];
    if (text is! String || text.trim().isEmpty) return null;
    if (startMs is! int || endMs is! int || startMs < 0 || endMs <= startMs) {
      return null;
    }
    final engine = raw['engine'];
    final confidence = raw['engineConfidence'];
    final reason = raw['reason'];
    return SecondaryOnlySuggestion(
      text: text,
      startMs: startMs,
      endMs: endMs,
      engine: engine is String && engine.isNotEmpty ? engine : null,
      engineConfidence: confidence is int ? confidence : null,
      reason: reason is String && reason.isNotEmpty
          ? reason
          : reasonNoPrimaryCounterpart,
    );
  }

  SecondaryOnlySuggestion shifted(Duration offset) => SecondaryOnlySuggestion(
    text: text,
    startMs: startMs + offset.inMilliseconds,
    endMs: endMs + offset.inMilliseconds,
    engine: engine,
    engineConfidence: engineConfidence,
    reason: reason,
  );

  bool matches(LyricLine line) =>
      line.text == text &&
      line.startTime.inMilliseconds == startMs &&
      line.endTime.inMilliseconds == endMs;

  String get _key => '$startMs|$endMs|$text';

  static Map<String, dynamic> wrap(Iterable<SecondaryOnlySuggestion> items) => {
    'version': version,
    'entries': [for (final item in items) item.toJson()],
  };

  /// Every well-formed record, regardless of whether a row still matches it.
  static List<SecondaryOnlySuggestion> read(Map<String, dynamic> metadata) {
    final raw = metadata[metadataKey];
    if (raw is! Map || raw['version'] != version || raw['entries'] is! List) {
      return const [];
    }
    final seen = <String>{};
    final result = <SecondaryOnlySuggestion>[];
    for (final entry in raw['entries'] as List) {
      final parsed = tryParse(entry);
      if (parsed == null || !seen.add(parsed._key)) continue;
      result.add(parsed);
    }
    return List.unmodifiable(result);
  }

  /// Row index -> suggestion, for rows that still carry the engine's exact
  /// text and timing. A row matched by two records (identical copies) is
  /// resolved once; a record no row matches is simply not shown.
  static Map<int, SecondaryOnlySuggestion> resolve(LyricDocument document) {
    final records = read(document.metadata);
    if (records.isEmpty) return const {};
    final byKey = {for (final record in records) record._key: record};
    final result = <int, SecondaryOnlySuggestion>{};
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      final key =
          '${line.startTime.inMilliseconds}|${line.endTime.inMilliseconds}|${line.text}';
      final record = byKey[key];
      if (record != null) result[index] = record;
    }
    return Map.unmodifiable(result);
  }

  /// Moves every record by [offset]; used when a chunk's local time becomes
  /// song time. Returns metadata unchanged when there are no records.
  static Map<String, dynamic> shiftMetadata(
    Map<String, dynamic> metadata,
    Duration offset,
  ) {
    if (!metadata.containsKey(metadataKey)) return metadata;
    final records = read(metadata);
    return {
      ...metadata,
      metadataKey: wrap(records.map((record) => record.shifted(offset))),
    };
  }
}
