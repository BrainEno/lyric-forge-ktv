/// Which local library store a [LocalStoreLoadIssue] belongs to.
enum LocalStoreKind { mediaLibrary, collections }

/// A store file was readable as a whole but some of its records were not.
///
/// The readable records stay visible, yet the store refuses every write until
/// the user repairs it: persisting the in-memory subset would silently drop the
/// unreadable rows from disk (#439).
class LocalStoreLoadIssue {
  const LocalStoreLoadIssue({
    required this.kind,
    required this.storePath,
    required this.unreadableRecords,
    required this.readableRecords,
    required this.detail,
  });

  final LocalStoreKind kind;

  /// The untouched file on disk.
  final String storePath;

  /// Records that could not be decoded and would be lost by a plain write.
  final int unreadableRecords;

  /// Records that were decoded and are currently shown.
  final int readableRecords;

  /// Developer-facing description of the first problem found.
  final String detail;

  @override
  String toString() =>
      'LocalStoreLoadIssue(${kind.name}, $unreadableRecords unreadable, '
      '$readableRecords readable, $storePath): $detail';
}

/// Thrown by a mutation while its store has an unresolved [LocalStoreLoadIssue].
class LocalStoreIncompleteException implements Exception {
  const LocalStoreIncompleteException(this.issue);

  final LocalStoreLoadIssue issue;

  @override
  String toString() =>
      'LocalStoreIncompleteException: the store at ${issue.storePath} was only '
      'partly readable (${issue.unreadableRecords} unreadable records). '
      'Writes are disabled to preserve the original file until it is repaired.';
}

/// Result of keeping a copy of a partly readable store and rewriting it with
/// only the readable records.
class LocalStoreRepairResult {
  const LocalStoreRepairResult({
    required this.preservedCopyPath,
    required this.keptRecords,
    required this.droppedRecords,
  });

  /// Byte-for-byte copy of the original file, kept beside the store.
  final String preservedCopyPath;
  final int keptRecords;
  final int droppedRecords;
}

/// Opt-in capability for local stores whose reads can be partial.
///
/// Presentation asks for [loadIssue] to explain why writes are refused and can
/// offer [repairKeepingReadableRecords] as an explicit, user-confirmed action.
abstract class LocalStoreIntegrity {
  /// The unresolved problem from the last successful load, or `null` when the
  /// store loaded completely. Throws if the store could not be loaded at all.
  Future<LocalStoreLoadIssue?> loadIssue();

  /// Copies the current store file to a new sibling file, verifies the copy,
  /// then rewrites the store with only the readable records and re-enables
  /// writes. Throws [StateError] when there is no issue to repair.
  Future<LocalStoreRepairResult> repairKeepingReadableRecords();
}
