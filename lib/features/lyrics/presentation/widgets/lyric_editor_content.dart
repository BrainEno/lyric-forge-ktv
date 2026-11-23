import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/recognition_review_summary.dart';
import '../../domain/models/secondary_only_suggestion.dart';
import '../../domain/services/lyric_draft_health_service.dart';
import '../../domain/services/lyric_line_batch_service.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../controllers/lyric_batch_edit_flow.dart';
import '../controllers/lyric_editor_document_controller.dart';
import 'line_inspector_sheet.dart';
import 'lyric_batch_selection_bar.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_editor_actions.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_editor_review_controls.dart';
import 'lyric_editor_toolbar.dart';
import 'lyric_edit_shortcuts.dart';
import 'lyric_inspector_pane.dart';
import 'lyric_line_jump.dart';
import 'lyric_list_pane.dart';
import 'lyric_proofread_menu_button.dart';
import 'lyric_recognition_summary_card.dart';
import 'lyric_tap_sync_prompt_card.dart';
import 'unsaved_lyric_edits_dialog.dart';

class LyricEditorLoadingState extends StatelessWidget {
  const LyricEditorLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('歌词校对')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class LyricEditorErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const LyricEditorErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('歌词校对')),
      body: AppErrorState(
        title: '加载歌词工程失败',
        message: '歌词工程暂时无法读取，可以重新加载一次。',
        onRetry: onRetry,
      ),
    );
  }
}

class LyricEditorContent extends StatelessWidget {
  final ProjectManifest project;
  final LyricDocument document;
  final bool hasChanges;

  /// Completes with `true` only when the current draft reached disk and the
  /// editor is clean; the save-and-leave path waits for it before popping.
  final Future<bool> Function() onSave;

  /// A save is in flight: save actions are disabled and leaving waits.
  final bool isSaving;

  // Grouped inputs, see lyric_editor_actions.dart and
  // lyric_editor_review_controls.dart (audit E-04).
  final LyricPlaybackControls player;
  final LyricReviewControls review;
  final LyricUndoRedoControls history;
  final LyricProofreadActions proofread;
  final LyricLineEditActions edits;
  final LyricAuditionControls audition;
  final VoidCallback onExport;
  final int focusRequestId;
  final int? focusLineIndex;
  final Set<int> manuallyEditedLineIndices;

  /// The editor, for choosing rows and editing them together (D-066). Null
  /// leaves batch edits out.
  final LyricEditorDocumentController? editor;

  const LyricEditorContent({
    super.key,
    required this.project,
    required this.document,
    required this.hasChanges,
    required this.onSave,
    this.isSaving = false,
    required this.player,
    required this.review,
    required this.history,
    this.proofread = LyricProofreadActions.none,
    required this.edits,
    required this.audition,
    required this.onExport,
    required this.focusRequestId,
    required this.focusLineIndex,
    this.manuallyEditedLineIndices = const {},
    this.editor,
  });

  Map<String, dynamic>? _fallbackCandidateFor(int index) {
    final raw = document.metadata['fallbackCandidates'];
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is! Map) continue;
      final candidate = Map<String, dynamic>.from(item);
      if (candidate['lineIndex'] == index) return candidate;
    }
    return null;
  }

  bool _isLineReviewed(int index) =>
      const LyricReviewDecisionService().isReviewed(document, index);

  Duration get _offset => document.globalOffset ?? Duration.zero;

  /// The row at the playhead, or null when the player is on another song.
  int? _currentPlaybackLineIndex() {
    final starts = [for (final line in document.lines) line.startTime];
    return player.lineAt(starts, offset: _offset);
  }

  Future<void> _showInspectorSheet(
    BuildContext context,
    int index, {
    bool autofocusText = false,
  }) async {
    if (index < 0 || index >= document.lines.length) return;
    review.onSelectLine(index);
    final spec = AppResponsive.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgElevated,
      builder: (sheetContext) {
        final isReviewed = _isLineReviewed(index);
        final canRecordDecision = review.canRecordDecision(
          index,
          isReviewed: isReviewed,
        );
        return LineInspectorSheet(
          editingText: autofocusText,
          previousLine: index > 0 ? document.lines[index - 1].text : null,
          nextLine: index + 1 < document.lines.length
              ? document.lines[index + 1].text
              : null,
          inspectorBuilder: (scrollController) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: spec.isCompact ? double.infinity : 720,
              ),
              child: LineInspector(
                key: ValueKey('sheet_inspector_$index'),
                scrollController: scrollController,
                index: index,
                line: document.lines[index],
                fallbackCandidate: _fallbackCandidateFor(index),
                secondarySuggestion: SecondaryOnlySuggestion.resolve(
                  document,
                )[index],
                isReviewed: isReviewed,
                onReviewDecision: canRecordDecision
                    ? (reviewed) {
                        review.onDecision(index, reviewed);
                        Navigator.of(sheetContext).pop();
                      }
                    : null,
                isCurrentPlaybackLine: _currentPlaybackLineIndex() == index,
                isPlaying: player.isPlaying,
                autofocusText: autofocusText,
                onUpdate: (updated) => edits.onUpdateLine(index, updated),
                onDelete: () {
                  edits.onDeleteLine(index);
                  Navigator.of(sheetContext).pop();
                },
                // The sheet shows one row; after a structural edit it would
                // describe a row that changed shape, so it closes like delete.
                onSplit: _splitLine == null
                    ? null
                    : (textOffset) {
                        _splitLine!(index, textOffset);
                        Navigator.of(sheetContext).pop();
                      },
                onMergeWithNext: _mergeWithNextFor(index) == null
                    ? null
                    : () {
                        edits.onMergeLineWithNext!(index);
                        Navigator.of(sheetContext).pop();
                      },
                onPreview: () => audition.onPreviewLine(index),
                onUsePlaybackAsStart: player.belongsToProject
                    ? () => edits.onSetStartFromPlayback(index)
                    : null,
                onUsePlaybackAsEnd: player.belongsToProject
                    ? () => edits.onSetEndFromPlayback(index)
                    : null,
                onSeekToTime: player.belongsToProject
                    ? (time) => player.onSeek(time + _offset)
                    : null,
                onEditWordTiming: proofread.onBatchTextTool == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        proofread.onBatchTextTool!(
                          LyricBatchTextTool.wordTimingEdit,
                        );
                      },
              ),
            ),
          ),
        );
      },
    );
  }

  void _requestSave() {
    unawaited(onSave());
  }

  /// The split callback the panes use. A paused playhead of this project is
  /// passed along as the audible break; while audio plays it is not, because
  /// a moving playhead says nothing about where the line should end.
  void Function(int index, int? textOffset)? get _splitLine {
    final split = edits.onSplitLine;
    if (split == null) return null;
    return (index, textOffset) =>
        split(index, textOffset, player.pausedPlayhead(offset: _offset));
  }

  /// Merge is offered only when there is a next row.
  ValueChanged<int>? _mergeWithNextFor(int index) =>
      index + 1 < document.lines.length ? edits.onMergeLineWithNext : null;

  /// Pops this editor once. A second completion (for example a shared save
  /// finishing for two back requests) must not pop the route below it.
  static void _popIfStillCurrent(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    Navigator.of(context).pop();
  }

  /// A menu callback for [tool], or null when the tools are unavailable.
  VoidCallback? _batchTool(LyricBatchTextTool tool) {
    final open = proofread.onBatchTextTool;
    return open == null ? null : () => open(tool);
  }

  /// Batch edits on the editor's chosen rows.
  LyricBatchEditFlow _batchFlow(LyricEditorDocumentController editor) =>
      LyricBatchEditFlow(
        editor: editor,
        onUndo: history.onUndo,
        onEdit: edits.onBatchEdit,
        audioDuration: project.audioAsset?.duration,
        auditionLineIndex: audition.activeLineIndex,
      );

  /// 跳到行 (D-067): asks for a row number or a time, then shows that row.
  /// A row the filter hides brings every row back first.
  Future<void> _jumpToLine(
    BuildContext context,
    LyricLineJumpController jump,
  ) async {
    if (document.lines.isEmpty) return;
    final target = await showLyricJumpToLineDialog(
      context,
      document: document,
      current: review.selectionWithin(document.lines.length),
    );
    if (target == null || !context.mounted) return;
    if (!review.visibleIndices(document.lines.length).contains(target)) {
      review.onFilterChanged(LyricReviewFilter.all);
    }
    review.onSelectLine(target);
    jump.jumpTo(target);
  }

  /// Rebuilt when the batch choice changes as well as with the document.
  @override
  Widget build(BuildContext context) {
    final editor = this.editor;
    return LyricLineJumpHost(
      builder: (context, jump) => editor == null
          ? _build(context, null, jump)
          : ListenableBuilder(
              listenable: editor,
              builder: (context, _) => _build(context, editor, jump),
            ),
    );
  }

  Widget _batchBar(
    BuildContext context,
    LyricEditorDocumentController editor,
    List<int> visibleIndices,
  ) {
    final flow = _batchFlow(editor);
    final chosen = editor.batchSelection;
    final reviewed = const LyricReviewDecisionService().reviewedIndices(
      document,
    );
    final everyShownChosen = visibleIndices.every(chosen.contains);
    return LyricBatchActionBar(
      count: chosen.length,
      allReviewed: chosen.isNotEmpty && chosen.every(reviewed.contains),
      canMerge:
          chosen.length >= 2 && LyricLineBatchService.isContiguous(chosen),
      onEnd: editor.endBatch,
      onSelectAll: everyShownChosen
          ? null
          : () => editor.selectAllBatch(visibleIndices),
      onMarkReviewed: (value) => flow.markReviewed(context, reviewed: value),
      onShift: () => unawaited(flow.shift(context)),
      onMerge: () => flow.merge(context),
      onCopy: () => flow.copy(context),
      onDelete: () => flow.delete(context),
    );
  }

  Widget _build(
    BuildContext context,
    LyricEditorDocumentController? editor,
    LyricLineJumpController jump,
  ) {
    final spec = AppResponsive.of(context);
    final currentPlaybackLine = _currentPlaybackLineIndex();
    final visibleIndices = review.visibleIndices(document.lines.length);
    final secondarySuggestions = SecondaryOnlySuggestion.resolve(document);
    final recognitionSummary = RecognitionReviewSummary.fromDocument(
      document,
      review.queue,
    );
    final selectedIndex = review.selectionWithin(document.lines.length);
    final firstQueued = review.firstQueuedLine;
    final batch = editor == null
        ? null
        : LyricBatchControls.of(
            editor,
            onDelete: () => _batchFlow(editor).delete(context),
          );
    final choosing = batch != null && batch.active;
    final VoidCallback? jumpToLine = document.lines.isEmpty
        ? null
        : () => unawaited(_jumpToLine(context, jump));

    return PopScope(
      canPop: !hasChanges && !isSaving && !choosing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Back first leaves batch mode, as on a phone's photo picker.
        if (choosing) {
          editor?.endBatch();
          return;
        }
        // A pending write decides whether leaving is safe; asking again while
        // it runs could pop twice or race the conflict dialog.
        if (isSaving) return;
        if (!hasChanges) return;
        final decision = await confirmUnsavedLyricEdits(context);
        if (!context.mounted) return;
        switch (decision) {
          // "保存并返回" leaves only after the write succeeded. A failure,
          // conflict, or newer edit keeps the editor and its draft open.
          case UnsavedLyricEditsDecision.save:
            final saved = await onSave();
            if (!saved || !context.mounted) return;
            _popIfStillCurrent(context);
          case UnsavedLyricEditsDecision.discard:
            _popIfStillCurrent(context);
          case UnsavedLyricEditsDecision.stay:
            break;
        }
      },
      child: LyricEditShortcuts(
        onUndo: history.onUndo,
        onRedo: history.onRedo,
        onSave: isSaving ? null : _requestSave,
        onFindReplace: _batchTool(LyricBatchTextTool.findReplace),
        onEndBatch: choosing ? editor?.endBatch : null,
        onJumpToLine: jumpToLine,
        child: Scaffold(
          backgroundColor: AppColors.bgBase,
          appBar: AppBar(
            backgroundColor: AppColors.bgBase,
            titleSpacing: AppSpacing.sm,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('歌词校对'),
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            actions: [
              if (spec.isCompactOrMedium || spec.isShort)
                LyricProofreadMenuButton.forActions(proofread, compact: true),
              LyricEditorOverflowMenu(
                onUndo: history.undoOrNull,
                onRedo: history.redoOrNull,
                undoLabel: history.availableUndoLabel,
                redoLabel: history.availableRedoLabel,
                canExport: document.lines.isNotEmpty,
                onExport: onExport,
                onJumpToLine: jumpToLine,
                onInsertAtPlayback: player.belongsToProject
                    ? edits.onInsertAtPlayback
                    : null,
                onOpenPlayer: project.canPlay
                    ? () => Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      )
                    : null,
              ),
              if (hasChanges || isSaving)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: spec.isCompact
                      ? IconButton.filledTonal(
                          key: const ValueKey('lyric_editor_save_action'),
                          tooltip: isSaving ? '正在保存…' : '保存修改',
                          onPressed: isSaving ? null : _requestSave,
                          icon: isSaving
                              ? const _SavingIndicator()
                              : const Icon(Icons.save_rounded),
                        )
                      : FilledButton.icon(
                          key: const ValueKey('lyric_editor_save_action'),
                          onPressed: isSaving ? null : _requestSave,
                          icon: isSaving
                              ? const _SavingIndicator()
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(isSaving ? '正在保存…' : '保存修改'),
                        ),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                LyricEditorToolbar(
                  document: document,
                  player: player,
                  review: review,
                  onUpdateOffset: edits.onUpdateOffset,
                  audition: audition,
                  proofread: proofread,
                ),
                Expanded(
                  child: document.lines.isEmpty
                      ? _EmptyLyricsState(onAddLine: edits.onAddLine)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final layout = AppResponsive.fromConstraints(
                              constraints,
                            );
                            final twoPane = layout.supportsTwoPane;
                            // The summary lives inside the list column, after
                            // the pane decision, so it can never push a desktop
                            // window into the single-pane layout.
                            // Untimed words (D-054) need 打轴 before anything
                            // else; the recognition summary has nothing to say.
                            final Widget? summaryCard = document.isUntimed
                                ? LyricTapSyncPromptCard(
                                    lineCount: document.lines.length,
                                    hasAudio: project.audioAsset != null,
                                    onStartTapSync: _batchTool(
                                      LyricBatchTextTool.tapSync,
                                    ),
                                  )
                                : recognitionSummary.hasRecognitionData
                                ? LyricRecognitionSummaryCard(
                                    summary: recognitionSummary,
                                    health: proofread.onBatchTextTool == null
                                        ? null
                                        : const LyricDraftHealthService()
                                              .cached(document),
                                    onOpenBatchTool: proofread.onBatchTextTool,
                                    onAutoProofread: proofread.onAutoProofread,
                                    onVocalCheckAction:
                                        proofread.onVocalCheckAction,
                                    // Through the unsaved-edits check.
                                    onBackToProject:
                                        Navigator.of(context).canPop()
                                        ? () => Navigator.of(context).maybePop()
                                        : null,
                                    onStartReview: firstQueued == null
                                        ? null
                                        : () {
                                            review.onFilterChanged(
                                              LyricReviewFilter.needsReview,
                                            );
                                            if (twoPane) {
                                              review.onSelectLine(firstQueued);
                                            } else {
                                              unawaited(
                                                _showInspectorSheet(
                                                  context,
                                                  firstQueued,
                                                ),
                                              );
                                            }
                                          },
                                  )
                                : null;
                            final listPane = LyricListPane(
                              document: document,
                              visibleIndices: visibleIndices,
                              review: review,
                              currentPlaybackLine: currentPlaybackLine,
                              focusRequestId: focusRequestId,
                              focusLineIndex: focusLineIndex,
                              fallbackCandidateFor: _fallbackCandidateFor,
                              secondarySuggestionIndices: secondarySuggestions
                                  .keys
                                  .toSet(),
                              activeAuditionLineIndex: audition.activeLineIndex,
                              auditionPlaying: audition.playing,
                              onPreviewLine: project.audioAsset == null
                                  ? null
                                  : audition.onPreviewLine,
                              onInsertedLineFocus: twoPane
                                  ? review.onSelectLine
                                  : (index) => _showInspectorSheet(
                                      context,
                                      index,
                                      autofocusText: true,
                                    ),
                              onSelectLine: twoPane
                                  ? review.onSelectLine
                                  : (index) =>
                                        _showInspectorSheet(context, index),
                              onUpdateLine: edits.onUpdateLine,
                              onDeleteLine: edits.onDeleteLine,
                              onSplitLine: _splitLine,
                              onMergeLineWithNext: edits.onMergeLineWithNext,
                              onSetStartFromPlayback: project.audioAsset == null
                                  ? null
                                  : edits.onSetStartFromPlayback,
                              onSetEndFromPlayback: project.audioAsset == null
                                  ? null
                                  : edits.onSetEndFromPlayback,
                              manuallyEditedLineIndices:
                                  manuallyEditedLineIndices,
                              batch: batch,
                              jump: jump,
                            );
                            final list = summaryCard == null
                                ? listPane
                                : Column(
                                    children: [
                                      summaryCard,
                                      Expanded(child: listPane),
                                    ],
                                  );

                            if (!twoPane) return list;

                            return Row(
                              children: [
                                Expanded(child: list),
                                const VerticalDivider(width: 1),
                                SizedBox(
                                  width: layout.sidePanelWidth,
                                  child: InspectorPane(
                                    document: document,
                                    review: review,
                                    player: player,
                                    fallbackCandidate: selectedIndex == null
                                        ? null
                                        : _fallbackCandidateFor(selectedIndex),
                                    secondarySuggestion: selectedIndex == null
                                        ? null
                                        : secondarySuggestions[selectedIndex],
                                    edits: edits,
                                    onSplitLine: _splitLine,
                                    onPreviewLine: audition.onPreviewLine,
                                    onEditWordTiming: _batchTool(
                                      LyricBatchTextTool.wordTimingEdit,
                                    ),
                                    autofocusText:
                                        selectedIndex != null &&
                                        selectedIndex == focusLineIndex,
                                    focusRequestId: focusRequestId,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                if (choosing)
                  _batchBar(context, editor!, visibleIndices)
                else
                  _BottomBar(
                    totalLines: document.lines.length,
                    visibleLines: visibleIndices.length,
                    hasChanges: hasChanges,
                    onAddLine: edits.onAddLine,
                    onStartBatch: editor == null || document.lines.isEmpty
                        ? null
                        : editor.startBatch,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A static marker rather than a spinner: a save can wait on the conflict
/// dialog, and an endless animation there would keep frames scheduled.
class _SavingIndicator extends StatelessWidget {
  const _SavingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.hourglass_top_rounded, size: 18);
  }
}

class _BottomBar extends StatelessWidget {
  final int totalLines;
  final int visibleLines;
  final bool hasChanges;
  final VoidCallback onAddLine;

  /// Turns batch mode on (D-066); null hides the 多选 button.
  final VoidCallback? onStartBatch;
  const _BottomBar({
    required this.totalLines,
    required this.visibleLines,
    required this.hasChanges,
    required this.onAddLine,
    this.onStartBatch,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final horizontalPadding = spec.pageGutter.clamp(12, 24).toDouble();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              visibleLines == totalLines
                  ? '$totalLines 行歌词'
                  : '显示 $visibleLines / $totalLines 行',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          if (hasChanges && !spec.isCompact) ...[
            const SizedBox(width: AppSpacing.sm),
            const LyricTinyBadge(label: '有未保存修改', warning: true),
          ],
          const Spacer(),
          if (onStartBatch case final start?)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: spec.isCompact
                  ? IconButton(
                      key: LyricBatchActionBar.startKey,
                      tooltip: LyricBatchStrings.startTooltip(),
                      onPressed: start,
                      icon: const Icon(Icons.checklist_rounded),
                    )
                  : Tooltip(
                      message: LyricBatchStrings.startTooltip(),
                      child: TextButton.icon(
                        key: LyricBatchActionBar.startKey,
                        onPressed: start,
                        icon: const Icon(Icons.checklist_rounded, size: 18),
                        label: const Text(LyricBatchStrings.start),
                      ),
                    ),
            ),
          if (spec.isCompact)
            IconButton.filledTonal(
              tooltip: '添加歌词行',
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded),
            )
          else
            FilledButton.tonalIcon(
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加歌词行'),
            ),
        ],
      ),
    );
  }
}

class _EmptyLyricsState extends StatelessWidget {
  final VoidCallback onAddLine;

  const _EmptyLyricsState({required this.onAddLine});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return AppEmptyState(
      icon: Icons.lyrics_outlined,
      title: '这个工程还没有歌词',
      message: '可以先返回工程页运行自动识别，也可以从这里手动建立第一行歌词。',
      actions: [
        FilledButton.icon(
          onPressed: onAddLine,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加第一行'),
          style: FilledButton.styleFrom(
            minimumSize: Size(
              spec.minimumInteractiveExtent,
              spec.minimumInteractiveExtent,
            ),
          ),
        ),
      ],
    );
  }
}
