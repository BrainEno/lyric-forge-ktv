import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/lyric_edit_history.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../../domain/services/lyric_timeline_insertion_service.dart';

/// A whole-editor state capture, used by "undo the last batch change".
///
/// Applying a reference alignment or a proofreading proposal replaces the
/// document wholesale and also moves the session's manual-edit marks and the
/// dirty flag, so undoing it needs more than the document: undoing only the
/// document would leave rows marked as manually edited that no longer were.
class LyricEditorSnapshot {
  final LyricDocument document;
  final Set<String> manuallyEditedLineIds;
  final int? selectedLineIndex;
  final bool hasChanges;

  /// Alignment and proofreading both guard this snapshot, but only a reference
  /// alignment has a before/after view worth opening.
  final bool isReferenceProofread;

  LyricEditorSnapshot({
    required this.document,
    required Set<String> manuallyEditedLineIds,
    required this.selectedLineIndex,
    required this.hasChanges,
    this.isReferenceProofread = false,
  }) : manuallyEditedLineIds = Set.unmodifiable(manuallyEditedLineIds);
}

/// What an edit did, for the little bit of UI the caller still has to do.
class LyricEditResult {
  /// False when the edit was a no-op (nothing to undo, index out of range, the
  /// review flag did not actually change).
  final bool applied;

  /// The edit replaced the whole document or moved the row the audition is
  /// playing, so the caller must drop the audition highlight. Whether playback
  /// also needs pausing depends on the player, which the caller owns.
  final bool clearsAudition;

  /// A message to show the user (undo/redo labels, or why nothing happened).
  final String? hint;

  /// Index of a freshly inserted row, so the list can focus it.
  final int? insertedLineIndex;

  const LyricEditResult({
    this.applied = true,
    this.clearsAudition = false,
    this.hint,
    this.insertedLineIndex,
  });

  const LyricEditResult.notApplied({String? message})
    : applied = false,
      clearsAudition = false,
      hint = message,
      insertedLineIndex = null;
}

/// Owns the lyric document being edited and everything that travels with it:
/// the dirty flag, the selected row, the set of manually edited line ids, and
/// the undo/redo history.
///
/// This used to be six fields spread across a 2,000-line `State`, where the
/// rules could only be checked by driving the whole editor. The rules worth
/// stating are all here:
///
/// * only a *text* change marks a row as manually edited — nudging a timestamp
///   is not an edit to protect from alignment;
/// * deleting a row also drops its manual-edit mark;
/// * the selection after a delete follows the row that took the deleted one's
///   place, and never points past the end;
/// * typing in one row collapses into a single undo step, while different rows
///   stay separate steps;
/// * undo/redo restore the manual-edit marks and dirty flag together with the
///   document, so undoing the only edit of a clean document is clean again
///   and no longer protects the row it had marked;
/// * undo/redo never restore a selection that no longer exists;
/// * any ordinary edit invalidates the batch-change snapshot, because undoing a
///   batch on top of a later edit would silently discard that edit.
class LyricEditorDocumentController extends ChangeNotifier {
  LyricEditorDocumentController({
    this.markerService = const LyricManualEditMarkerService(),
    this.reviewDecisionService = const LyricReviewDecisionService(),
    this.insertionService = const LyricTimelineInsertionService(),
    LyricEditHistory? history,
    DateTime Function()? clock,
  }) : history = history ?? LyricEditHistory(),
       _clock = clock ?? DateTime.now;

  final LyricManualEditMarkerService markerService;
  final LyricReviewDecisionService reviewDecisionService;
  final LyricTimelineInsertionService insertionService;
  final LyricEditHistory history;
  final DateTime Function() _clock;

  static const LyricDocument _emptyDocument = LyricDocument(
    language: 'zh',
    lines: <LyricLine>[],
  );

  LyricDocument? _document;
  bool _hasChanges = false;
  int? _selectedLineIndex;
  final Set<String> _manuallyEditedLineIds = <String>{};
  LyricEditorSnapshot? _alignmentSnapshot;

  LyricDocument? get document => _document;

  bool get hasChanges => _hasChanges;

  int? get selectedLineIndex => _selectedLineIndex;

  /// Line ids the user edited by hand in this session (or restored from the
  /// document's metadata). Reference alignment and proofreading skip them.
  Set<String> get manuallyEditedLineIds =>
      UnmodifiableSetView(_manuallyEditedLineIds);

  /// Current indices of the protected rows, resolved through stable line ids.
  Set<int> get protectedIndices {
    final document = _document;
    if (document == null) return const <int>{};
    return markerService.protectedIndices(document, _manuallyEditedLineIds);
  }

  /// The batch change that can still be undone as a unit, if any.
  LyricEditorSnapshot? get alignmentSnapshot => _alignmentSnapshot;

  bool get canUndo => history.canUndo;

  bool get canRedo => history.canRedo;

  String? get undoLabel => history.undoLabel;

  String? get redoLabel => history.redoLabel;

  void select(int? index) {
    if (_selectedLineIndex == index) return;
    _selectedLineIndex = index;
    notifyListeners();
  }

  /// A freshly loaded document is a new baseline: undo must never walk back into
  /// a different song, so history is cleared here rather than by the caller.
  LyricDocument load(LyricDocument loaded) {
    final document = markerService.assignMissingLineIds(loaded);
    _document = document;
    _hasChanges = false;
    _alignmentSnapshot = null;
    history.clear();
    _manuallyEditedLineIds
      ..clear()
      ..addAll(markerService.restore(document));
    if (document.lines.isEmpty) {
      _selectedLineIndex = null;
    } else if (_selectedLineIndex == null ||
        _selectedLineIndex! >= document.lines.length) {
      _selectedLineIndex = 0;
    }
    notifyListeners();
    return document;
  }

  void markSaved() {
    if (!_hasChanges && _alignmentSnapshot == null) return;
    _hasChanges = false;
    _alignmentSnapshot = null;
    notifyListeners();
  }

  /// The document as it should be written to disk, with this session's manual
  /// edit marks persisted into its metadata.
  LyricDocument documentForSave() {
    final document = _document;
    if (document == null) {
      throw StateError('Nothing to save: no document is loaded.');
    }
    return document.copyWith(
      metadata: markerService.persist(document, _manuallyEditedLineIds),
    );
  }

  LyricEditResult undo() {
    final current = _document;
    if (current == null) return const LyricEditResult.notApplied();
    final snapshot = history.undo(
      current,
      manuallyEditedLineIds: _manuallyEditedLineIds,
      hasChanges: _hasChanges,
      now: _clock(),
    );
    if (snapshot == null) {
      return const LyricEditResult.notApplied(message: '没有可撤销的修改');
    }
    _restoreHistoryEntry(snapshot);
    notifyListeners();
    return LyricEditResult(hint: '已撤销：${snapshot.label}', clearsAudition: true);
  }

  LyricEditResult redo() {
    final current = _document;
    if (current == null) return const LyricEditResult.notApplied();
    final snapshot = history.redo(
      current,
      manuallyEditedLineIds: _manuallyEditedLineIds,
      hasChanges: _hasChanges,
      now: _clock(),
    );
    if (snapshot == null) {
      return const LyricEditResult.notApplied(message: '没有可重做的修改');
    }
    _restoreHistoryEntry(snapshot);
    notifyListeners();
    return LyricEditResult(hint: '已重做：${snapshot.label}', clearsAudition: true);
  }

  /// Appends an empty row after the last one, or at five seconds when the
  /// document is empty.
  LyricEditResult addLine() {
    final current = _document ?? _emptyDocument;
    final lines = List<LyricLine>.from(current.lines);
    final lastEndTime = lines.isNotEmpty
        ? lines.last.endTime
        : const Duration(seconds: 5);

    _recordEdit('添加歌词行');
    lines.add(
      LyricLine(
        text: '',
        startTime: lastEndTime,
        endTime: lastEndTime + const Duration(seconds: 5),
      ),
    );
    _document = markerService.assignMissingLineIds(
      current.copyWith(
        lines: lines,
        metadata: clearIndexedReviewMetadata(current.metadata),
      ),
    );
    _selectedLineIndex = lines.length - 1;
    _markEdited();
    notifyListeners();
    return const LyricEditResult();
  }

  /// Inserts a row at [position], keeping the doc sorted by start time.
  LyricEditResult insertLineAt(Duration position, {Duration? audioDuration}) {
    final current = _document ?? _emptyDocument;
    final insertion = insertionService.insertAtPlayback(
      lines: current.lines,
      position: position,
      audioDuration: audioDuration,
    );
    final lines = List<LyricLine>.from(current.lines)
      ..insert(insertion.index, insertion.line);

    _recordEdit('在播放位置插入一行');
    _document = markerService.assignMissingLineIds(
      current.copyWith(
        lines: lines,
        metadata: clearIndexedReviewMetadata(current.metadata),
      ),
    );
    _selectedLineIndex = insertion.index;
    _markEdited();
    notifyListeners();
    return LyricEditResult(insertedLineIndex: insertion.index);
  }

  /// Replaces one row.
  ///
  /// [auditionTarget] tells the controller whether this row is the one the
  /// bounded audition is playing; only a *timing* change to that row makes the
  /// audition stale, because the highlight refers to a window that no longer
  /// matches the line.
  LyricEditResult updateLine(
    int index,
    LyricLine updatedLine, {
    bool auditionTarget = false,
  }) {
    final document = _document;
    if (document == null || index < 0 || index >= document.lines.length) {
      return const LyricEditResult.notApplied();
    }

    final previousLine = document.lines[index];
    final timingChanged =
        previousLine.startTime != updatedLine.startTime ||
        previousLine.endTime != updatedLine.endTime;
    final invalidateAudition = auditionTarget && timingChanged;

    // Repeated edits to one line inside the merge window are a single undo
    // step: retyping a lyric should not cost one undo per keystroke burst.
    // The history entry must be recorded before the manual-edit mark below
    // is added, or the snapshot would capture the post-edit marks and undo
    // could never un-mark the row.
    _recordEdit('修改第 ${index + 1} 行', mergeKey: 'line:$index');
    if (previousLine.text != updatedLine.text) {
      final lineId = previousLine.id;
      if (lineId != null) _manuallyEditedLineIds.add(lineId);
    }
    final lines = List<LyricLine>.from(document.lines);
    lines[index] = updatedLine;
    _document = document.copyWith(lines: lines);
    _markEdited();
    notifyListeners();
    return LyricEditResult(clearsAudition: invalidateAudition);
  }

  LyricEditResult deleteLine(int index, {bool auditionTarget = false}) {
    final document = _document;
    if (document == null || index < 0 || index >= document.lines.length) {
      return const LyricEditResult.notApplied();
    }

    final removedLine = document.lines[index];
    _recordEdit('删除第 ${index + 1} 行');
    final lines = List<LyricLine>.from(document.lines)..removeAt(index);
    _document = document.copyWith(
      lines: lines,
      metadata: clearIndexedReviewMetadata(document.metadata),
    );
    if (removedLine.id != null) {
      _manuallyEditedLineIds.remove(removedLine.id);
    }

    if (lines.isEmpty) {
      _selectedLineIndex = null;
    } else if (_selectedLineIndex == index) {
      _selectedLineIndex = index.clamp(0, lines.length - 1).toInt();
    } else if (_selectedLineIndex != null && _selectedLineIndex! > index) {
      _selectedLineIndex = _selectedLineIndex! - 1;
    }
    _markEdited();
    notifyListeners();
    return LyricEditResult(clearsAudition: auditionTarget);
  }

  LyricEditResult updateGlobalOffset(Duration offset) {
    _recordEdit('调整全局偏移', mergeKey: 'offset');
    _document = _document?.copyWith(globalOffset: offset);
    _markEdited();
    notifyListeners();
    return const LyricEditResult(clearsAudition: true);
  }

  /// Flips the review flag of one row. Marking review is a user-visible change,
  /// so it is undoable like any other edit.
  LyricEditResult setLineReviewed(int index, {required bool reviewed}) {
    final document = _document;
    if (document == null || index < 0 || index >= document.lines.length) {
      return const LyricEditResult.notApplied();
    }
    // Re-marking a row that is already in the requested state is not an edit:
    // the decision service would still return a fresh document (new timestamp),
    // which used to become a phantom undo step.
    if (reviewDecisionService.isReviewed(document, index) == reviewed) {
      return const LyricEditResult.notApplied();
    }
    final updated = reviewDecisionService.setReviewed(
      document,
      index,
      reviewed: reviewed,
    );
    if (identical(updated, document)) return const LyricEditResult.notApplied();

    _recordEdit(
      reviewed ? '标记第 ${index + 1} 行为已复核' : '取消第 ${index + 1} 行的复核标记',
    );
    _document = updated;
    _markEdited();
    notifyListeners();
    return const LyricEditResult();
  }

  /// Swaps in a document produced elsewhere (alignment, proofreading, restore).
  ///
  /// [keepBatchSnapshot] keeps the pre-change state so the batch can be undone
  /// as one unit; any later ordinary edit drops it again.
  LyricEditResult replaceDocument(
    LyricDocument after, {
    required String label,
    required int? selectedLineIndex,
    bool keepBatchSnapshot = false,
    bool isReferenceProofread = false,
  }) {
    final snapshot = keepBatchSnapshot && _document != null
        ? _captureSnapshot(isReferenceProofread: isReferenceProofread)
        : null;
    _recordEdit(label);
    _document = after;
    _selectedLineIndex = selectedLineIndex;
    _markEdited();
    _alignmentSnapshot = snapshot;
    notifyListeners();
    return const LyricEditResult(clearsAudition: true);
  }

  /// Restores the single-slot alignment backup, keeping only the manual-edit
  /// marks that still describe a surviving row.
  LyricEditResult restoreDocument(
    LyricDocument restored, {
    required String label,
  }) {
    _recordEdit(label);
    final document = markerService.assignMissingLineIds(restored);
    // 备份文档保留了各行的稳定标识：会话内标记按标识取交集继续生效，
    // 备份元数据中持久化的标记一并恢复；旧版本备份没有标识时自然失配。
    final sessionSurvivors = markerService.prune(
      document,
      _manuallyEditedLineIds,
    );
    _manuallyEditedLineIds
      ..clear()
      ..addAll(sessionSurvivors)
      ..addAll(markerService.restore(document));
    _document = document;
    _markEdited();

    if (document.lines.isEmpty) {
      _selectedLineIndex = null;
    } else if (_selectedLineIndex != null) {
      _selectedLineIndex = _selectedLineIndex!
          .clamp(0, document.lines.length - 1)
          .toInt();
    }
    notifyListeners();
    return const LyricEditResult(clearsAudition: true);
  }

  /// Reverts the batch change captured by [replaceDocument].
  LyricEditResult undoBatchChange() {
    final snapshot = _alignmentSnapshot;
    if (snapshot == null) return const LyricEditResult.notApplied();
    // The reversal is itself an edit, so it can be redone with the history.
    _recordEdit('撤销参考对齐');
    _document = snapshot.document;
    _manuallyEditedLineIds
      ..clear()
      ..addAll(snapshot.manuallyEditedLineIds);
    _selectedLineIndex = snapshot.selectedLineIndex;
    _hasChanges = snapshot.hasChanges;
    _alignmentSnapshot = null;
    notifyListeners();
    return const LyricEditResult(clearsAudition: true);
  }

  /// Drops `fallbackCandidates` and its counts.
  ///
  /// Those metadata entries are indexed by row, so inserting or deleting a row
  /// would silently attach a candidate to the wrong line.
  static Map<String, dynamic> clearIndexedReviewMetadata(
    Map<String, dynamic> metadata,
  ) {
    return Map<String, dynamic>.from(metadata)
      ..remove('fallbackCandidates')
      ..remove('fallbackCandidateCount')
      ..remove('fallbackAppliedCount');
  }

  void _restoreHistoryEntry(LyricEditSnapshot snapshot) {
    _document = snapshot.document;
    final index = snapshot.selectedLineIndex;
    _selectedLineIndex =
        index != null && index >= 0 && index < snapshot.document.lines.length
        ? index
        : null;
    _manuallyEditedLineIds
      ..clear()
      ..addAll(snapshot.manuallyEditedLineIds);
    _hasChanges = snapshot.hasChanges;
    _alignmentSnapshot = null;
  }

  void _markEdited() {
    _hasChanges = true;
    _alignmentSnapshot = null;
  }

  void _recordEdit(String label, {String? mergeKey}) {
    final document = _document;
    if (document == null) return;
    history.record(
      document,
      label: label,
      mergeKey: mergeKey,
      selectedLineIndex: _selectedLineIndex,
      manuallyEditedLineIds: _manuallyEditedLineIds,
      hasChanges: _hasChanges,
      now: _clock(),
    );
  }

  LyricEditorSnapshot _captureSnapshot({bool isReferenceProofread = false}) {
    return LyricEditorSnapshot(
      document: _document!,
      manuallyEditedLineIds: _manuallyEditedLineIds,
      selectedLineIndex: _selectedLineIndex,
      hasChanges: _hasChanges,
      isReferenceProofread: isReferenceProofread,
    );
  }
}
