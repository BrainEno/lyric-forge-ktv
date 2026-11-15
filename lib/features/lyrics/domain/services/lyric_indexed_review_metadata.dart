/// Keeps row-indexed review evidence attached to the right rows when the
/// editor inserts or deletes a row.
///
/// `fallbackCandidates` (the other engine's text for a row) and
/// `secondaryOnlyLineIndices` are stored by row index. The editor used to drop
/// them on any structural edit, because a shifted index would attach a
/// candidate to the wrong line. That was safe but expensive: rejecting a single
/// "建议补入" row (a delete) erased every remaining dual-engine candidate in the
/// song. Shifting the indices keeps them correct instead.
///
/// Malformed evidence is still dropped exactly as before; nothing is guessed.
class LyricIndexedReviewMetadata {
  const LyricIndexedReviewMetadata._();

  static const String candidatesKey = 'fallbackCandidates';
  static const String candidateCountKey = 'fallbackCandidateCount';
  static const String appliedCountKey = 'fallbackAppliedCount';
  static const String secondaryOnlyIndicesKey = 'secondaryOnlyLineIndices';
  static const String secondaryOnlyCountKey = 'secondaryOnlyLineCount';

  /// Metadata after the row at [removedIndex] was deleted. Evidence for that
  /// row disappears with it; later rows move up by one.
  static Map<String, dynamic> afterRowRemoved(
    Map<String, dynamic> metadata,
    int removedIndex,
  ) => _remap(metadata, (index) {
    if (index == removedIndex) return null;
    return index > removedIndex ? index - 1 : index;
  });

  /// Metadata after a new row was inserted at [insertedIndex]. The new row has
  /// no engine evidence; rows at or after it move down by one.
  static Map<String, dynamic> afterRowInserted(
    Map<String, dynamic> metadata,
    int insertedIndex,
  ) => _remap(metadata, (index) => index >= insertedIndex ? index + 1 : index);

  /// The pre-remap behaviour: remove every row-indexed candidate field.
  static Map<String, dynamic> clear(Map<String, dynamic> metadata) =>
      Map<String, dynamic>.from(metadata)
        ..remove(candidatesKey)
        ..remove(candidateCountKey)
        ..remove(appliedCountKey);

  static Map<String, dynamic> _remap(
    Map<String, dynamic> metadata,
    int? Function(int index) map,
  ) {
    var result = Map<String, dynamic>.from(metadata);

    if (result.containsKey(candidatesKey)) {
      final remapped = _remapCandidates(result[candidatesKey], map);
      if (remapped == null) {
        result = clear(result);
      } else {
        result[candidatesKey] = remapped;
        result[candidateCountKey] = remapped.length;
      }
    } else {
      // Counts without the list they count cannot be kept consistent.
      result = clear(result);
    }

    final rawIndices = result[secondaryOnlyIndicesKey];
    if (rawIndices is List) {
      final remapped = <int>[];
      var valid = true;
      for (final value in rawIndices) {
        if (value is! int || value < 0) {
          valid = false;
          break;
        }
        final next = map(value);
        if (next != null) remapped.add(next);
      }
      if (valid) {
        remapped.sort();
        result[secondaryOnlyIndicesKey] = remapped;
        result[secondaryOnlyCountKey] = remapped.length;
      } else {
        result
          ..remove(secondaryOnlyIndicesKey)
          ..remove(secondaryOnlyCountKey);
      }
    }
    return result;
  }

  /// Null when the stored value is not a well-formed candidate list.
  static List<Map<String, dynamic>>? _remapCandidates(
    Object? raw,
    int? Function(int index) map,
  ) {
    if (raw is! List) return null;
    final result = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map) return null;
      final lineIndex = entry['lineIndex'];
      if (lineIndex is! int || lineIndex < 0) return null;
      final next = map(lineIndex);
      if (next == null) continue;
      result.add({...Map<String, dynamic>.from(entry), 'lineIndex': next});
    }
    return result;
  }
}
