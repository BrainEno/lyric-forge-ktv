import 'package:flutter/foundation.dart';

import '../../../project/domain/models/lyric_document.dart';
import 'lyric_batch_text_edit.dart';

// Groups of LyricEditorContent inputs that belong together.
//
// The editor content took 50 constructor arguments, and the screen built it
// with one 110-line call in which undo, proofreading, row edits and audition
// were interleaved (audit E-04). Each group below is one concern; the screen
// assembles them and the content reads `history.onUndo`,
// `proofread.onReferenceAlignment` and so on.

/// Undo and redo, with the labels shown in their tooltips.
@immutable
class LyricEditHistory {
  const LyricEditHistory({
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
    this.onReferenceAlignment,
    this.onReferenceProofread,
    this.onProofreadV2,
    this.onUndoReferenceAlignment,
    this.onViewAlignmentComparison,
    this.onRestoreAlignment,
    this.onUnifyChineseScript,
    this.onBatchTextTool,
  });

  /// Nothing available, as for a project without lyrics.
  static const LyricProofreadActions none = LyricProofreadActions();

  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onReferenceProofread;
  final VoidCallback? onProofreadV2;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;
  final VoidCallback? onUnifyChineseScript;

  /// Opens one of the batch text tools (find-and-replace, repeated-line
  /// consistency, text clean-up, word timing).
  final ValueChanged<LyricBatchTextTool>? onBatchTextTool;
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
