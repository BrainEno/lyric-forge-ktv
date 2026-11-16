import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../widgets/lyric_batch_text_edit.dart';
import '../widgets/lyric_find_replace_dialog.dart';
import '../widgets/lyric_repetition_consistency_dialog.dart';
import '../widgets/lyric_structure_dialog.dart';
import '../widgets/lyric_text_cleanup_dialog.dart';
import 'lyric_editor_proofreading_coordinator.dart';

/// Runs a batch text tool against a snapshot of the editing document and
/// hands the confirmed result to the editor as one undoable change.
///
/// Kept apart from the editor screen so the screen stays a thin host: the
/// tool dialogs build their result from pure domain plans, and this class
/// only sequences the dialog and the stale-document check.
class LyricBatchTextToolsCoordinator {
  const LyricBatchTextToolsCoordinator({required this.host});

  final LyricEditorProofreadFlowHost host;

  static const String staleMessage = '歌词在预览期间已被修改，本次批量更改未应用，请重新打开。';

  Future<void> open(
    LyricBatchTextTool tool, {
    required ProjectManifest project,
    required LyricDocument? document,
  }) async {
    if (document == null || document.lines.isEmpty) return;
    final context = host.proofreadContext;
    final revision = host.proofreadDocumentRevision;
    final protectedIndices = host.proofreadManuallyEditedLineIndices;

    final edit = await _show(
      tool,
      context,
      project: project,
      document: document,
      protectedIndices: protectedIndices,
    );
    if (edit == null || !context.mounted || !host.proofreadIsMounted) return;
    if (!host.proofreadIsCurrent(revision)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(staleMessage)));
      return;
    }
    host.applyProofreadDocument(
      document: edit.document,
      label: edit.label,
      selectedLineIndex: edit.selectedLineIndex,
      isReferenceProofread: false,
      message: edit.message,
      markManuallyEditedLineIds: edit.manuallyEditedLineIds,
    );
  }

  Future<LyricBatchTextEdit?> _show(
    LyricBatchTextTool tool,
    BuildContext context, {
    required ProjectManifest project,
    required LyricDocument document,
    required Set<int> protectedIndices,
  }) => switch (tool) {
    LyricBatchTextTool.findReplace => showLyricFindReplaceDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
    ),
    LyricBatchTextTool.repetitionConsistency =>
      showLyricRepetitionConsistencyDialog(
        context,
        document: document,
        protectedIndices: protectedIndices,
        onPreviewLine: project.audioAsset == null
            ? null
            : (index) => host.previewProofreadLine(project, index),
      ),
    LyricBatchTextTool.textCleanup => showLyricTextCleanupDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
    ),
    LyricBatchTextTool.lineStructure => showLyricStructureDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
  };
}
