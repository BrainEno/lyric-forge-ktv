import '../../../project/domain/models/lyric_document.dart';

/// One reversible step: the document as it was *before* an edit, plus enough
/// context to tell the user what pressing undo will do.
///
/// The document alone is not the whole reversible state: the session's
/// manual-edit marks decide which rows later proofreading must protect, and
/// the dirty flag decides whether leaving the editor prompts to save. Both
/// travel with the snapshot so undoing an edit also un-marks the row it had
/// marked and can return the editor to its clean baseline.
class LyricEditSnapshot {
  final LyricDocument document;
  final String label;

  /// Index that was selected when the edit happened, restored with the
  /// document so undo puts the user back where they were.
  final int? selectedLineIndex;

  /// Manual-edit marks as they were before the edit.
  final Set<String> manuallyEditedLineIds;

  /// Whether the editor had unsaved changes before the edit. Undoing the
  /// only edit of a clean document restores `false`, so the user is not
  /// prompted to save a document that matches what is on disk.
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
    Set<String>? manuallyEditedLineIds,
    this.hasChanges = false,
    this.mergeKey,
  }) : manuallyEditedLineIds = Set.unmodifiable(
         manuallyEditedLineIds ?? const <String>{},
       );
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
    Set<String>? manuallyEditedLineIds,
    bool hasChanges = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (mergeKey != null && _undo.isNotEmpty) {
      final last = _undo.last;
      if (last.mergeKey == mergeKey &&
          at.difference(last.recordedAt) <= mergeWindow) {
        // The merged step still reverts the whole burst, so it keeps the
        // document and session state captured before the burst started.
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

  /// Returns the state to restore, and makes [current] redoable. The caller
  /// passes the session state that belongs to [current] so redoing restores
  /// the marks and dirtiness of the state being left, not just its document.
  LyricEditSnapshot? undo(
    LyricDocument current, {
    Set<String>? manuallyEditedLineIds,
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

  /// Returns the state to restore, and makes [current] undoable again.
  LyricEditSnapshot? redo(
    LyricDocument current, {
    Set<String>? manuallyEditedLineIds,
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

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
