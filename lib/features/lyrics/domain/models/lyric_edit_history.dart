import '../../../project/domain/models/lyric_document.dart';

/// One reversible step: the document as it was *before* an edit, plus enough
/// context to tell the user what pressing undo will do.
class LyricEditSnapshot {
  final LyricDocument document;
  final String label;

  /// Index that was selected when the edit happened, restored with the
  /// document so undo puts the user back where they were.
  final int? selectedLineIndex;

  /// Session state that affects save output and the unsaved-changes prompt.
  final Set<String> manuallyEditedLineIds;
  final bool hasChanges;

  /// Edits sharing a merge key inside the merge window collapse into one step.
  /// Used so retyping a single line does not cost one undo per character.
  final String? mergeKey;

  final DateTime recordedAt;

  LyricEditSnapshot({
    required this.document,
    required this.label,
    required this.recordedAt,
    this.selectedLineIndex,
    Set<String> manuallyEditedLineIds = const <String>{},
    this.hasChanges = false,
    this.mergeKey,
  }) : manuallyEditedLineIds = Set<String>.unmodifiable(manuallyEditedLineIds);
}

/// A bounded two-stack edit history for the lyric editor.
///
/// The editor already had one one-shot snapshot, but only for reference
/// alignment (`撤销最近更改`), and only until the next edit. Anything else — a
/// mis-typed line, a deleted row, a global offset nudge, an applied proofreading
/// proposal — was unrecoverable. This history is the general form: every edit
/// pushes the previous document, [maxEntries] steps are kept, and redo works
/// until the next new edit.
///
/// It is deliberately not part of the document: undo state is about this
/// editing session, and persisting it would let a user "undo" into a document
/// that no longer matches what is on disk.
class LyricEditHistory {
  /// Steps kept before the oldest is dropped. The review asked for at least 50
  /// because five mistaken edits in a row were the reported case, with room to
  /// spare for measurement work.
  static const int maxEntries = 50;

  /// Consecutive edits with the same merge key within this window are one step.
  static const Duration mergeWindow = Duration(seconds: 2);

  final List<LyricEditSnapshot> _undo = <LyricEditSnapshot>[];
  final List<LyricEditSnapshot> _redo = <LyricEditSnapshot>[];

  int get undoDepth => _undo.length;

  int get redoDepth => _redo.length;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  /// What undo would revert, for the menu label. Null when there is nothing.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// What redo would reapply.
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Records the document as it was before an edit.
  ///
  /// Call this *before* mutating. When [mergeKey] matches the previous entry and
  /// that entry is younger than [mergeWindow], the older snapshot is kept and
  /// simply refreshed: the step reverts the whole burst rather than its last
  /// keystroke.
  void record(
    LyricDocument document, {
    required String label,
    String? mergeKey,
    int? selectedLineIndex,
    Set<String> manuallyEditedLineIds = const <String>{},
    bool hasChanges = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (mergeKey != null && _undo.isNotEmpty) {
      final last = _undo.last;
      if (last.mergeKey == mergeKey &&
          at.difference(last.recordedAt) <= mergeWindow) {
        _undo[_undo.length - 1] = LyricEditSnapshot(
          document: last.document,
          label: label,
          selectedLineIndex: last.selectedLineIndex,
          manuallyEditedLineIds: last.manuallyEditedLineIds,
          hasChanges: last.hasChanges,
          mergeKey: mergeKey,
          recordedAt: at,
        );
        _redo.clear();
        return;
      }
    }

    _undo.add(
      LyricEditSnapshot(
        document: document,
        label: label,
        selectedLineIndex: selectedLineIndex,
        manuallyEditedLineIds: manuallyEditedLineIds,
        hasChanges: hasChanges,
        mergeKey: mergeKey,
        recordedAt: at,
      ),
    );
    if (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
    // A new edit invalidates the redo branch, the same way it does in every
    // editor: you cannot replay a future that no longer follows from the past.
    _redo.clear();
  }

  /// Returns the document to restore, and makes [current] redoable.
  LyricEditSnapshot? undo(
    LyricDocument current, {
    Set<String> manuallyEditedLineIds = const <String>{},
    bool hasChanges = false,
    DateTime? now,
  }) {
    if (_undo.isEmpty) return null;
    final snapshot = _undo.removeLast();
    _redo.add(
      LyricEditSnapshot(
        document: current,
        label: snapshot.label,
        selectedLineIndex: snapshot.selectedLineIndex,
        manuallyEditedLineIds: manuallyEditedLineIds,
        hasChanges: hasChanges,
        recordedAt: now ?? DateTime.now(),
      ),
    );
    return snapshot;
  }

  /// Returns the document to restore, and makes [current] undoable again.
  LyricEditSnapshot? redo(
    LyricDocument current, {
    Set<String> manuallyEditedLineIds = const <String>{},
    bool hasChanges = false,
    DateTime? now,
  }) {
    if (_redo.isEmpty) return null;
    final snapshot = _redo.removeLast();
    _undo.add(
      LyricEditSnapshot(
        document: current,
        label: snapshot.label,
        selectedLineIndex: snapshot.selectedLineIndex,
        manuallyEditedLineIds: manuallyEditedLineIds,
        hasChanges: hasChanges,
        recordedAt: now ?? DateTime.now(),
      ),
    );
    if (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
    return snapshot;
  }

  /// Rebase history dirtiness against the state just written to disk. Most
  /// older states become dirty, but a no-op edit may still point at this exact
  /// saved state and should not trigger an unsaved-changes prompt.
  void markSaved(LyricDocument document, Set<String> manuallyEditedLineIds) {
    for (var index = 0; index < _undo.length; index++) {
      _undo[index] = _withSavedBaseline(
        _undo[index],
        document,
        manuallyEditedLineIds,
      );
    }
    for (var index = 0; index < _redo.length; index++) {
      _redo[index] = _withSavedBaseline(
        _redo[index],
        document,
        manuallyEditedLineIds,
      );
    }
  }

  LyricEditSnapshot _withSavedBaseline(
    LyricEditSnapshot snapshot,
    LyricDocument savedDocument,
    Set<String> savedManualMarks,
  ) {
    // Compare the persisted shape structurally: map insertion order is not a
    // document change, and serializing two full JSON strings is unnecessary.
    final sameDocument = _deepEquals(
      snapshot.document.toJson(),
      savedDocument.toJson(),
    );
    final sameManualMarks =
        snapshot.manuallyEditedLineIds.length == savedManualMarks.length &&
        snapshot.manuallyEditedLineIds.containsAll(savedManualMarks);
    return LyricEditSnapshot(
      document: snapshot.document,
      label: snapshot.label,
      recordedAt: snapshot.recordedAt,
      selectedLineIndex: snapshot.selectedLineIndex,
      manuallyEditedLineIds: snapshot.manuallyEditedLineIds,
      hasChanges: !(sameDocument && sameManualMarks),
      mergeKey: snapshot.mergeKey,
    );
  }

  bool _deepEquals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List<Object?> && right is List<Object?>) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
