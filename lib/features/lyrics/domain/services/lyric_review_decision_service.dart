import '../../../project/domain/models/lyric_document.dart';

/// Persists an explicit human review decision against a stable line ID and the
/// line's current text/timing fingerprint. Editing either invalidates the
/// decision automatically without depending on mutable row indexes.
class LyricReviewDecisionService {
  static const String metadataKey = 'lyricReviewDecisions';

  const LyricReviewDecisionService();

  bool isReviewed(LyricDocument document, int lineIndex) {
    if (lineIndex < 0 || lineIndex >= document.lines.length) return false;
    final line = document.lines[lineIndex];
    final id = line.id;
    if (id == null || id.isEmpty) return false;

    final decisions = _readDecisions(document.metadata[metadataKey]);
    final record = decisions[id];
    if (record is! Map) return false;
    return record['fingerprint'] == fingerprint(line);
  }

  Set<int> reviewedIndices(LyricDocument document) => {
    for (var index = 0; index < document.lines.length; index++)
      if (isReviewed(document, index)) index,
  };

  LyricDocument setReviewed(
    LyricDocument document,
    int lineIndex, {
    required bool reviewed,
    DateTime? reviewedAt,
  }) {
    if (lineIndex < 0 || lineIndex >= document.lines.length) return document;
    final line = document.lines[lineIndex];
    final id = line.id;
    if (id == null || id.isEmpty) return document;

    final existing = _readDecisions(document.metadata[metadataKey]);
    final byLineId = <String, LyricLine>{
      for (final candidate in document.lines)
        if (candidate.id != null && candidate.id!.isNotEmpty)
          candidate.id!: candidate,
    };
    final valid = <String, dynamic>{};
    for (final entry in existing.entries) {
      final currentLine = byLineId[entry.key];
      final record = entry.value;
      if (currentLine == null || record is! Map) continue;
      if (record['fingerprint'] != fingerprint(currentLine)) continue;
      valid[entry.key] = _stringKeyedRecord(record);
    }

    if (reviewed) {
      valid[id] = <String, dynamic>{
        'fingerprint': fingerprint(line),
        'reviewedAt': (reviewedAt ?? DateTime.now()).toIso8601String(),
      };
    } else {
      valid.remove(id);
    }

    final metadata = Map<String, dynamic>.from(document.metadata);
    if (valid.isEmpty) {
      metadata.remove(metadataKey);
    } else {
      metadata[metadataKey] = valid;
    }
    return document.copyWith(metadata: metadata);
  }

  /// Deterministic 32-bit FNV-1a fingerprint. It is a cache key, not a security
  /// primitive; including the time interval means timing edits require review.
  String fingerprint(LyricLine line) {
    var hash = 0x811c9dc5;
    void add(int value) {
      hash = ((hash ^ value) * 0x01000193) & 0xffffffff;
    }

    for (final rune in line.text.runes) {
      add(rune);
    }
    add(0xff);
    for (final value in [
      line.startTime.inMilliseconds,
      line.endTime.inMilliseconds,
    ]) {
      var remaining = value;
      for (var byte = 0; byte < 4; byte++) {
        add(remaining & 0xff);
        remaining >>= 8;
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> _readDecisions(Object? raw) {
    if (raw is! Map) return const {};
    final decisions = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is String) decisions[entry.key as String] = entry.value;
    }
    return decisions;
  }

  Map<String, dynamic> _stringKeyedRecord(Map raw) {
    final record = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is String) record[entry.key as String] = entry.value;
    }
    return record;
  }
}
