import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/services/lyric_span_rerecognition.dart';
import '../widgets/lyric_asr_loop_dialog.dart';
import '../widgets/lyric_batch_text_edit.dart';
import '../widgets/lyric_find_replace_dialog.dart';
import '../widgets/lyric_missed_repeat_dialog.dart';
import '../widgets/lyric_pace_check_dialog.dart';
import '../widgets/lyric_repetition_consistency_dialog.dart';
import '../widgets/lyric_span_recognition_dialog.dart';
import '../widgets/lyric_structure_dialog.dart';
import '../widgets/lyric_tap_sync_dialog.dart';
import '../widgets/lyric_text_cleanup_dialog.dart';
import '../widgets/lyric_timeline_repair_dialog.dart';
import '../widgets/lyric_timing_shift_dialog.dart';
import '../widgets/lyric_word_tap_dialog.dart';
import '../widgets/lyric_word_timing_check_dialog.dart';
import '../widgets/lyric_word_timing_edit_dialog.dart';
import 'lyric_editor_proofreading_coordinator.dart';

/// Runs a batch text tool against a snapshot of the editing document and
/// hands the confirmed result to the editor as one undoable change.
///
/// Kept apart from the editor screen so the screen stays a thin host: the
/// tool dialogs build their result from pure domain plans, and this class
/// only sequences the dialog and the stale-document check.
class LyricBatchTextToolsCoordinator {
  const LyricBatchTextToolsCoordinator({
    required this.host,
    this.spanRecognizer,
  });

  final LyricEditorProofreadFlowHost host;

  /// Runs "re-run this stretch"; null when the app has no local runtime.
  final LyricSpanRecognizer? spanRecognizer;

  static const String staleMessage = '歌词在预览期间已被修改，本次批量更改未应用，请重新打开。';

  static const String tapSyncNeedsAudio = '本工程没有音频，无法打轴。';

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
    LyricBatchTextTool.timelineRepair => showLyricTimelineRepairDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
      audioDuration: project.audioAsset?.duration,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
    LyricBatchTextTool.timingShift => showLyricTimingShiftDialog(
      context,
      document: document,
      selectedIndex: host.proofreadSelectedLineIndex,
      audioDuration: project.audioAsset?.duration,
      playhead: pausedPlayhead(project, document),
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
    LyricBatchTextTool.paceCheck => showLyricPaceCheckDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
    LyricBatchTextTool.tapSync => _openTapSync(
      context,
      project,
      document,
      (start, transport) => showLyricTapSyncDialog(
        context,
        document: document,
        startIndex: start,
        transport: transport,
      ),
    ),
    LyricBatchTextTool.wordTap => _openTapSync(
      context,
      project,
      document,
      (start, transport) => showLyricWordTapDialog(
        context,
        document: document,
        startIndex: start,
        transport: transport,
      ),
    ),
    LyricBatchTextTool.wordTimingCheck => showLyricWordTimingCheckDialog(
      context,
      document: document,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
    LyricBatchTextTool.wordTimingEdit =>
      project.audioAsset == null
          ? showLyricWordTimingEditDialog(
              context,
              document: document,
              index: _selectedRow(document),
            )
          : _openTapSync(
              context,
              project,
              document,
              (start, transport) => showLyricWordTimingEditDialog(
                context,
                document: document,
                index: start,
                transport: transport,
              ),
            ),
    LyricBatchTextTool.asrLoopCheck => showLyricAsrLoopDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
    ),
    LyricBatchTextTool.spanRecognition => _openSpanRecognition(
      context,
      project,
      document,
      protectedIndices,
    ),
    LyricBatchTextTool.missedRepeatCheck => showLyricMissedRepeatDialog(
      context,
      document: document,
      protectedIndices: protectedIndices,
      audioDuration: project.audioAsset?.duration,
      onPreviewLine: project.audioAsset == null
          ? null
          : (index) => host.previewProofreadLine(project, index),
      onPreviewSpan: project.audioAsset == null
          ? null
          : (index, start, end) =>
                _previewSpan(project, document, index, start, end),
    ),
  };

  /// Re-running a stretch needs the project's audio and a local runtime;
  /// without either the user is told why instead of seeing a dead dialog.
  Future<LyricBatchTextEdit?> _openSpanRecognition(
    BuildContext context,
    ProjectManifest project,
    LyricDocument document,
    Set<int> protectedIndices,
  ) async {
    final recognizer = spanRecognizer;
    final unavailable = project.audioAsset == null
        ? LyricSpanRecognitionStrings.noAudio
        : recognizer == null
        ? LyricSpanRecognitionStrings.noRecognizer
        : null;
    if (unavailable != null || recognizer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unavailable ?? LyricSpanRecognitionStrings.noRecognizer,
          ),
        ),
      );
      return null;
    }
    return showLyricSpanRecognitionDialog(
      context,
      document: document,
      projectId: project.id,
      recognizer: recognizer,
      selectedIndex: host.proofreadSelectedLineIndex,
      protectedIndices: protectedIndices,
      audioDuration: project.audioAsset?.duration,
      onPreviewSpan: (index, start, end) =>
          _previewSpan(project, document, index, start, end),
    );
  }

  /// Plays an arbitrary stretch of the song, such as the empty stretch after
  /// a chant row, through the bounded line audition. Row [index] only
  /// anchors the audition; the stretch is played on the document's timeline.
  void _previewSpan(
    ProjectManifest project,
    LyricDocument document,
    int index,
    Duration start,
    Duration end,
  ) {
    if (index < 0 || index >= document.lines.length || end <= start) return;
    host.previewProofreadTimedLine(
      project,
      index,
      document.lines[index].copyWith(startTime: start, endTime: end),
      document.globalOffset ?? Duration.zero,
    );
  }

  /// Tap-to-sync (by row or by word) and word fine-tuning need this
  /// project's audio loaded and free-running: a bounded line audition would stop the song at the row's end. When other
  /// audio (or nothing) is loaded, the selected row's audition loads the
  /// project and is then released and paused, so the dialog opens on a
  /// quiet, loaded player.
  Future<LyricBatchTextEdit?> _openTapSync(
    BuildContext context,
    ProjectManifest project,
    LyricDocument document,
    Future<LyricBatchTextEdit?> Function(
      int startIndex,
      LyricTapSyncTransport transport,
    )
    show,
  ) async {
    if (project.audioAsset == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(tapSyncNeedsAudio)));
      return null;
    }
    final start = _selectedRow(document);
    final audio = host.proofreadAudioService;
    try {
      final item = host.proofreadPlaybackSession.currentState.currentItem;
      if (item?.projectId != project.id) {
        await host.previewProofreadLine(project, start);
        host.proofreadAudition.clear();
        if (audio.currentState.isPlaying) await audio.pause();
      } else if (host.proofreadAudition.isActive) {
        host.proofreadAudition.clear();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法加载音频：$error')));
      }
      return null;
    }
    if (!context.mounted || !host.proofreadIsMounted) return null;
    return show(start, LyricTapSyncTransport.fromAudio(audio));
  }

  /// The selected row, or the first one.
  int _selectedRow(LyricDocument document) {
    final selected = host.proofreadSelectedLineIndex ?? 0;
    final last = document.lines.length - 1;
    return selected < 0 ? 0 : (selected > last ? last : selected);
  }

  /// The playhead on [document]'s timeline when this project's audio is
  /// loaded and paused, so the timing tools can offer it as a target time.
  /// A moving playhead is not offered: it is already somewhere else by the
  /// time the user reads it.
  Duration? pausedPlayhead(ProjectManifest project, LyricDocument document) {
    final item = host.proofreadPlaybackSession.currentState.currentItem;
    if (item?.projectId != project.id) return null;
    final playback = host.proofreadAudioService.currentState;
    if (playback.isPlaying) return null;
    final position =
        playback.position - (document.globalOffset ?? Duration.zero);
    return position.isNegative ? Duration.zero : position;
  }
}
