import 'package:flutter/foundation.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../controllers/lyric_editor_document_controller.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_vocal_check_request.dart';

// Groups of LyricEditorContent inputs that belong together.
//
// The editor content took 50 constructor arguments, and the screen built it
// with one 110-line call in which undo, proofreading, row edits and audition
// were interleaved (audit E-04). Each group below is one concern; the screen
// assembles them and the content reads `history.onUndo`,
// `proofread.onReferenceAlignment` and so on.

/// Undo and redo, with the labels shown in their tooltips.
@immutable
class LyricUndoRedoControls {
  const LyricUndoRedoControls({
    required this.onUndo,
    required this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.undoLabel,
    this.redoLabel,
  });

  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;

  /// What undo would revert, as shown in its tooltip; null when nothing.
  final String? undoLabel;
  final String? redoLabel;

  /// [onUndo] when there is something to undo, otherwise null, so a button
  /// built from it is disabled.
  VoidCallback? get undoOrNull => canUndo ? onUndo : null;
  VoidCallback? get redoOrNull => canRedo ? onRedo : null;

  /// The tooltip labels, only while the action is available.
  String? get availableUndoLabel => canUndo ? undoLabel : null;
  String? get availableRedoLabel => canRedo ? redoLabel : null;
}

/// Whole-document proofreading tools. Each is null while it is unavailable,
/// for example while there are no lyrics or no alignment to undo.
@immutable
class LyricProofreadActions {
  const LyricProofreadActions({
    this.onAutoProofread,
    this.autoProofreadRunning = false,
    this.onReferenceAlignment,
    this.onSmartProofread,
    this.onUndoReferenceAlignment,
    this.onViewAlignmentComparison,
    this.onRestoreAlignment,
    this.onBatchTextTool,
    this.onVocalCheckAction,
  });

  /// Nothing available, as for a project without lyrics.
  static const LyricProofreadActions none = LyricProofreadActions();

  /// The tools for the current document. The text tools need lyrics, smart
  /// proofreading and 一键校对 run one pass at a time, and the alignment follow-ups
  /// depend only on the applied [alignment], so they stay available after
  /// every row was deleted. Only a reference alignment, not a proofreading
  /// pass, has a before/after comparison.
  factory LyricProofreadActions.forDocument({
    required bool hasLines,
    bool smartProofreadRunning = false,
    LyricEditorSnapshot? alignment,
    bool canRestore = false,
    required VoidCallback referenceAlignment,
    required VoidCallback smartProofread,
    VoidCallback? autoProofread,
    required VoidCallback undoAlignment,
    required VoidCallback viewComparison,
    required VoidCallback restoreAlignment,
    required ValueChanged<LyricBatchTextTool> batchTextTool,
    ValueChanged<LyricVocalCheckRequest>? vocalCheckAction,
  }) {
    final comparable = alignment != null && !alignment.isReferenceProofread;
    return LyricProofreadActions(
      onAutoProofread: hasLines && !smartProofreadRunning
          ? autoProofread
          : null,
      autoProofreadRunning: smartProofreadRunning,
      onReferenceAlignment: hasLines ? referenceAlignment : null,
      onSmartProofread: hasLines && !smartProofreadRunning
          ? smartProofread
          : null,
      onUndoReferenceAlignment: alignment == null ? null : undoAlignment,
      onViewAlignmentComparison: comparable ? viewComparison : null,
      onRestoreAlignment: canRestore ? restoreAlignment : null,
      onBatchTextTool: hasLines ? batchTextTool : null,
      onVocalCheckAction: hasLines ? vocalCheckAction : null,
    );
  }

  /// 一键校对: online lyric plus every safe correction in one undoable pass.
  final VoidCallback? onAutoProofread;

  /// A proofreading pass is running; the toolbar shows progress instead of
  /// the 一键校对 button.
  final bool autoProofreadRunning;

  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onSmartProofread;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;

  /// Opens one of the batch text tools (find-and-replace, repeated-line
  /// consistency, text clean-up, word timing).
  final ValueChanged<LyricBatchTextTool>? onBatchTextTool;

  /// Runs a one-click follow-up of the vocal check from the recognition
  /// summary (D-045): recognise a given stretch, restore removed rows.
  final ValueChanged<LyricVocalCheckRequest>? onVocalCheckAction;
}

/// Edits to single rows and to the document offset.
@immutable
class LyricLineEditActions {
  const LyricLineEditActions({
    required this.onAddLine,
    required this.onInsertAtPlayback,
    required this.onUpdateLine,
    required this.onDeleteLine,
    this.onSplitLine,
    this.onMergeLineWithNext,
    required this.onUpdateOffset,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
  });

  final VoidCallback onAddLine;
  final VoidCallback onInsertAtPlayback;
  final void Function(int index, LyricLine line) onUpdateLine;
  final ValueChanged<int> onDeleteLine;

  /// Splits a row at a text offset (null: the natural break nearest the sung
  /// middle). The third argument is the paused playhead on the timeline when
  /// this project's audio is paused, which then marks the audible break.
  final void Function(int index, int? textOffset, Duration? playhead)?
  onSplitLine;

  /// Merges a row with the one after it.
  final ValueChanged<int>? onMergeLineWithNext;
  final ValueChanged<Duration> onUpdateOffset;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;
}

/// Playing one row on its own while proofreading.
@immutable
class LyricAuditionControls {
  const LyricAuditionControls({
    required this.onPreviewLine,
    this.activeLineIndex,
    this.playing = false,
    this.loopCurrentLine = false,
    required this.onLoopCurrentLineChanged,
  });

  final ValueChanged<int> onPreviewLine;

  /// The row being auditioned, if any.
  final int? activeLineIndex;

  /// The project's audio is playing.
  final bool playing;

  /// Repeat the auditioned row until the user moves on.
  final bool loopCurrentLine;
  final ValueChanged<bool> onLoopCurrentLineChanged;
}
