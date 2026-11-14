import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_editor_toolbar.dart';
import 'lyric_edit_shortcuts.dart';
import 'lyric_inspector_pane.dart';
import 'lyric_list_pane.dart';
import 'lyric_proofread_menu_button.dart';
import 'unsaved_lyric_edits_dialog.dart';

class LyricEditorLoadingState extends StatelessWidget {
  const LyricEditorLoadingState();

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

  const LyricEditorErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('歌词校对')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('加载歌词工程失败'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class LyricEditorContent extends StatelessWidget {
  final ProjectManifest project;
  final LyricDocument document;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final bool hasChanges;
  final Map<int, LyricReviewPriority> reviewPriorityByIndex;
  final LyricReviewQueue reviewQueue;
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;
  final bool loopCurrentLineAudition;
  final ValueChanged<bool> onLoopCurrentLineAuditionChanged;
  final bool followPlayback;
  final int? selectedLineIndex;
  final LyricReviewFilter filter;
  final ValueChanged<LyricReviewFilter> onFilterChanged;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<int> onSelectLine;
  final void Function(int, bool) onReviewDecision;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final String? undoLabel;
  final String? redoLabel;
  final VoidCallback onExport;
  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onReferenceProofread;
  final VoidCallback? onProofreadV2;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;
  final VoidCallback onAddLine;
  final VoidCallback onInsertAtPlayback;
  final ValueChanged<Duration> onSeekPlayback;
  final int focusRequestId;
  final int? focusLineIndex;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<Duration> onUpdateOffset;
  final ValueChanged<int> onPreviewLine;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;
  final VoidCallback onTogglePlayback;
  final Set<int> manuallyEditedLineIndices;

  const LyricEditorContent({
    required this.project,
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.hasChanges,
    required this.reviewPriorityByIndex,
    required this.reviewQueue,
    required this.activeAuditionLineIndex,
    required this.auditionPlaying,
    required this.loopCurrentLineAudition,
    required this.onLoopCurrentLineAuditionChanged,
    required this.followPlayback,
    required this.selectedLineIndex,
    required this.filter,
    required this.onFilterChanged,
    required this.onFollowPlaybackChanged,
    required this.onSelectLine,
    required this.onReviewDecision,
    required this.onSave,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.undoLabel,
    required this.redoLabel,
    required this.onExport,
    required this.onReferenceAlignment,
    required this.onReferenceProofread,
    required this.onProofreadV2,
    required this.onUndoReferenceAlignment,
    required this.onViewAlignmentComparison,
    required this.onRestoreAlignment,
    required this.onAddLine,
    required this.onInsertAtPlayback,
    required this.onSeekPlayback,
    required this.focusRequestId,
    required this.focusLineIndex,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onUpdateOffset,
    required this.onPreviewLine,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
    required this.onTogglePlayback,
    this.manuallyEditedLineIndices = const {},
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

  int? _currentPlaybackLineIndex() {
    if (!playbackBelongsToProject || document.lines.isEmpty) return null;
    final offset = document.globalOffset ?? Duration.zero;
    for (var index = document.lines.length - 1; index >= 0; index--) {
      final shifted = document.lines[index].startTime + offset;
      final effective = shifted.isNegative ? Duration.zero : shifted;
      if (playback.position >= effective) return index;
    }
    return 0;
  }

  List<int> _visibleIndices() {
    final indices = <int>[];
    for (var index = 0; index < document.lines.length; index++) {
      final include = switch (filter) {
        LyricReviewFilter.all => true,
        LyricReviewFilter.needsReview => reviewQueue.needsReview(index),
        LyricReviewFilter.lowConfidence => reviewQueue.isLowConfidence(index),
      };
      if (include) indices.add(index);
    }
    if (filter != LyricReviewFilter.all) {
      indices.sort((left, right) {
        final byPriority = (reviewPriorityByIndex[right]?.score ?? 0).compareTo(
          reviewPriorityByIndex[left]?.score ?? 0,
        );
        return byPriority != 0 ? byPriority : left.compareTo(right);
      });
    }
    return indices;
  }

  Future<void> _showInspectorSheet(
    BuildContext context,
    int index, {
    bool autofocusText = false,
  }) async {
    if (index < 0 || index >= document.lines.length) return;
    onSelectLine(index);
    final spec = AppResponsive.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgElevated,
      builder: (sheetContext) {
        final sheetSpec = AppResponsive.of(sheetContext);
        final heightFactor = sheetSpec.isShort ? 0.96 : 0.88;
        final isReviewed = _isLineReviewed(index);
        final canRecordDecision =
            isReviewed || reviewPriorityByIndex.containsKey(index);
        return FractionallySizedBox(
          heightFactor: heightFactor,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: spec.isCompact ? double.infinity : 720,
              ),
              child: LineInspector(
                key: ValueKey('sheet_inspector_$index'),
                index: index,
                line: document.lines[index],
                fallbackCandidate: _fallbackCandidateFor(index),
                isReviewed: isReviewed,
                onReviewDecision: canRecordDecision
                    ? (reviewed) {
                        onReviewDecision(index, reviewed);
                        Navigator.of(sheetContext).pop();
                      }
                    : null,
                isCurrentPlaybackLine:
                    playbackBelongsToProject &&
                    _currentPlaybackLineIndex() == index,
                isPlaying: playbackBelongsToProject && playback.isPlaying,
                autofocusText: autofocusText,
                onUpdate: (updated) => onUpdateLine(index, updated),
                onDelete: () {
                  onDeleteLine(index);
                  Navigator.of(sheetContext).pop();
                },
                onPreview: () => onPreviewLine(index),
                onUsePlaybackAsStart: playbackBelongsToProject
                    ? () => onSetStartFromPlayback(index)
                    : null,
                onUsePlaybackAsEnd: playbackBelongsToProject
                    ? () => onSetEndFromPlayback(index)
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final currentPlaybackLine = _currentPlaybackLineIndex();
    final visibleIndices = _visibleIndices();
    final selectedIndex =
        selectedLineIndex != null &&
            selectedLineIndex! >= 0 &&
            selectedLineIndex! < document.lines.length
        ? selectedLineIndex
        : null;

    return PopScope(
      canPop: !hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!hasChanges) return;
        final decision = await confirmUnsavedLyricEdits(context);
        if (!context.mounted) return;
        switch (decision) {
          // "保存并返回" used to pop with `false` and call onSave(), which saved
          // the document but left the user on the editor, so the button did the
          // opposite of what it said. Saving now always ends with leaving.
          case UnsavedLyricEditsDecision.save:
            onSave();
            Navigator.of(context).pop();
          case UnsavedLyricEditsDecision.discard:
            Navigator.of(context).pop();
          case UnsavedLyricEditsDecision.stay:
            break;
        }
      },
      child: LyricEditShortcuts(
        onUndo: onUndo,
        onRedo: onRedo,
        onSave: onSave,
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
                LyricProofreadMenuButton(
                  compact: true,
                  onProofreadV2: onProofreadV2,
                  onReferenceAlignment: onReferenceAlignment,
                  onReferenceProofread: onReferenceProofread,
                  onViewComparison: onViewAlignmentComparison,
                  onUndoAlignment: onUndoReferenceAlignment,
                  onRestoreBackup: onRestoreAlignment,
                ),
              LyricEditorOverflowMenu(
                onUndo: canUndo ? onUndo : null,
                onRedo: canRedo ? onRedo : null,
                undoLabel: canUndo ? undoLabel : null,
                redoLabel: canRedo ? redoLabel : null,
                canExport: document.lines.isNotEmpty,
                onExport: onExport,
                onInsertAtPlayback: playbackBelongsToProject
                    ? onInsertAtPlayback
                    : null,
                onOpenPlayer: project.canPlay
                    ? () => Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      )
                    : null,
              ),
              if (hasChanges)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: spec.isCompact
                      ? IconButton.filledTonal(
                          tooltip: '保存修改',
                          onPressed: onSave,
                          icon: const Icon(Icons.save_rounded),
                        )
                      : FilledButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('保存修改'),
                        ),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                LyricEditorToolbar(
                  document: document,
                  playback: playback,
                  playbackBelongsToProject: playbackBelongsToProject,
                  review: reviewQueue,
                  filter: filter,
                  loopCurrentLineAudition: loopCurrentLineAudition,
                  onLoopCurrentLineAuditionChanged:
                      onLoopCurrentLineAuditionChanged,
                  followPlayback: followPlayback,
                  onFilterChanged: onFilterChanged,
                  onFollowPlaybackChanged: onFollowPlaybackChanged,
                  onUpdateOffset: onUpdateOffset,
                  onTogglePlayback: onTogglePlayback,
                  onSeekPlayback: onSeekPlayback,
                  onReferenceAlignment: onReferenceAlignment,
                  onReferenceProofread: onReferenceProofread,
                  onProofreadV2: onProofreadV2,
                  onUndoReferenceAlignment: onUndoReferenceAlignment,
                  onViewAlignmentComparison: onViewAlignmentComparison,
                  onRestoreAlignment: onRestoreAlignment,
                ),
                Expanded(
                  child: document.lines.isEmpty
                      ? _EmptyLyricsState(onAddLine: onAddLine)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final layout = AppResponsive.fromConstraints(
                              constraints,
                            );
                            final twoPane = layout.supportsTwoPane;
                            final list = LyricListPane(
                              document: document,
                              visibleIndices: visibleIndices,
                              selectedIndex: selectedIndex,
                              currentPlaybackLine: currentPlaybackLine,
                              followPlayback: followPlayback,
                              focusRequestId: focusRequestId,
                              focusLineIndex: focusLineIndex,
                              fallbackCandidateFor: _fallbackCandidateFor,
                              reviewPriorityByIndex: reviewPriorityByIndex,
                              filter: filter,
                              activeAuditionLineIndex: activeAuditionLineIndex,
                              auditionPlaying: auditionPlaying,
                              onPreviewLine: project.audioAsset == null
                                  ? null
                                  : onPreviewLine,
                              onInsertedLineFocus: twoPane
                                  ? onSelectLine
                                  : (index) => _showInspectorSheet(
                                      context,
                                      index,
                                      autofocusText: true,
                                    ),
                              onSelectLine: twoPane
                                  ? onSelectLine
                                  : (index) =>
                                        _showInspectorSheet(context, index),
                              onUpdateLine: onUpdateLine,
                              onDeleteLine: onDeleteLine,
                              onSetStartFromPlayback: project.audioAsset == null
                                  ? null
                                  : onSetStartFromPlayback,
                              onSetEndFromPlayback: project.audioAsset == null
                                  ? null
                                  : onSetEndFromPlayback,
                              manuallyEditedLineIndices:
                                  manuallyEditedLineIndices,
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
                                    selectedIndex: selectedIndex,
                                    fallbackCandidate: selectedIndex == null
                                        ? null
                                        : _fallbackCandidateFor(selectedIndex),
                                    isReviewed:
                                        selectedIndex != null &&
                                        _isLineReviewed(selectedIndex),
                                    onReviewDecision:
                                        selectedIndex != null &&
                                            (_isLineReviewed(selectedIndex) ||
                                                reviewPriorityByIndex
                                                    .containsKey(selectedIndex))
                                        ? (reviewed) {
                                            onReviewDecision(
                                              selectedIndex,
                                              reviewed,
                                            );
                                          }
                                        : null,
                                    playback: playback,
                                    playbackBelongsToProject:
                                        playbackBelongsToProject,
                                    currentPlaybackLine: currentPlaybackLine,
                                    onUpdateLine: onUpdateLine,
                                    onDeleteLine: onDeleteLine,
                                    onPreviewLine: onPreviewLine,
                                    onSetStartFromPlayback:
                                        onSetStartFromPlayback,
                                    onSetEndFromPlayback: onSetEndFromPlayback,
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
                _BottomBar(
                  totalLines: document.lines.length,
                  visibleLines: visibleIndices.length,
                  hasChanges: hasChanges,
                  onAddLine: onAddLine,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int totalLines;
  final int visibleLines;
  final bool hasChanges;
  final VoidCallback onAddLine;
  const _BottomBar({
    required this.totalLines,
    required this.visibleLines,
    required this.hasChanges,
    required this.onAddLine,
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
      decoration: const BoxDecoration(
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
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: EdgeInsets.all(spec.isCompact ? AppSpacing.lg : AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '这个工程还没有歌词',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '可以先返回工程页运行自动识别，也可以从这里手动建立第一行歌词。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加第一行'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
