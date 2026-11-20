import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import 'lyric_editor_review_controls.dart';
import 'lyric_editor_toolbar.dart';
import 'lyric_inline_editor_row.dart';
import 'lyric_list_logic.dart';
import 'lyric_list_states.dart';
import 'lyric_review_row.dart';
import 'timestamp_edit_dialog.dart';

// The rows and the time dialog moved to their own files; importers of the
// list keep reaching them through it.
export 'lyric_inline_editor_row.dart' show InlineLyricEditorRow;
export 'lyric_review_row.dart' show LyricReviewRow, LyricRowMenuAction;
export 'timestamp_edit_dialog.dart'
    show TimestampEditDialog, LyricTimeInput, editLyricLineTime;

/// The editor's scrolling line list: one row per lyric line, in either editable
/// or review mode.
///
/// Extracted from the editor screen (Phase 4.1) with its parameters unchanged
/// so the behaviour stayed byte-for-byte while it became testable on its own.
/// The review queue's priorities, the filter, the follow toggle and the
/// selection now arrive as the editor's [LyricReviewControls] instead of five
/// separate arguments (audit E-04); the getters below read them from it.
///
/// The rows, the inline editor, the time dialog and the empty states live in
/// their own files, and the search, candidate and keyboard rules in
/// lyric_list_logic.dart; this file keeps the list's state (search text,
/// the row being edited, scrolling and focus).
class LyricListPane extends StatefulWidget {
  final LyricDocument document;

  /// The rows the filter shows, worked out once by the editor because the
  /// bottom bar counts them too.
  final List<int> visibleIndices;

  /// Priorities, filter, follow toggle and selection.
  final LyricReviewControls review;
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;

  /// The row at the playhead, worked out once by the editor because the
  /// inspector marks it too.
  final int? currentPlaybackLine;
  final int focusRequestId;
  final int? focusLineIndex;
  final Map<String, dynamic>? Function(int) fallbackCandidateFor;

  /// Rows only the secondary engine heard, shown as "建议补入".
  final Set<int> secondarySuggestionIndices;
  final ValueChanged<int>? onPreviewLine;
  final ValueChanged<int> onInsertedLineFocus;

  /// What tapping a row does. On wide layouts this is the review group's
  /// `onSelectLine`; on narrow ones the editor opens the row in a sheet.
  final ValueChanged<int> onSelectLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;

  /// Splits a row at a text offset; the list always passes null, which splits
  /// at the natural break nearest the sung middle.
  final void Function(int index, int? textOffset)? onSplitLine;

  /// Merges a row with the next one.
  final ValueChanged<int>? onMergeLineWithNext;
  final ValueChanged<int>? onSetStartFromPlayback;
  final ValueChanged<int>? onSetEndFromPlayback;
  final Set<int> manuallyEditedLineIndices;

  const LyricListPane({
    required this.document,
    required this.visibleIndices,
    required this.review,
    required this.activeAuditionLineIndex,
    required this.auditionPlaying,
    required this.currentPlaybackLine,
    required this.focusRequestId,
    required this.focusLineIndex,
    required this.fallbackCandidateFor,
    this.secondarySuggestionIndices = const {},
    required this.onPreviewLine,
    required this.onInsertedLineFocus,
    required this.onSelectLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    this.onSplitLine,
    this.onMergeLineWithNext,
    this.onSetStartFromPlayback,
    this.onSetEndFromPlayback,
    this.manuallyEditedLineIndices = const {},
  });

  LyricReviewFilter get filter => review.filter;
  bool get followPlayback => review.followPlayback;

  /// The selected row while it is still a row of [document].
  int? get selectedIndex => review.selectionWithin(document.lines.length);

  /// Clears the review filter; offered when the filter hides every line,
  /// and null while every line is already shown.
  VoidCallback? get onShowAllLines {
    if (review.filter == LyricReviewFilter.all) return null;
    return () => review.onFilterChanged(LyricReviewFilter.all);
  }

  @override
  State<LyricListPane> createState() => _LyricListPaneState();
}

class _LyricListPaneState extends State<LyricListPane> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _listFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  int? _editingIndex;
  String _searchQuery = '';

  List<int> get _filteredIndices => LyricListSearch.filter(
    widget.document,
    widget.visibleIndices,
    _searchQuery,
  );

  bool get _showsSearch =>
      widget.document.lines.length >= LyricListStateText.searchFromLines;

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
    if (widget.focusRequestId > 0) {
      _scheduleInsertedLineFocus();
    }
  }

  @override
  void didUpdateWidget(covariant LyricListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequestId != widget.focusRequestId) {
      _scheduleInsertedLineFocus();
    }
    final editing = _editingIndex;
    if (editing != null &&
        (editing < 0 || editing >= widget.document.lines.length)) {
      _editingIndex = null;
    }
    final visibleIndicesChanged = !sameLyricIndices(
      oldWidget.visibleIndices,
      widget.visibleIndices,
    );
    // The old matches are worked out on the old document: its rows may no
    // longer exist in the new one after a delete or a merge.
    final searchChanged =
        _searchQuery.trim().isNotEmpty &&
        !sameLyricIndices(
          LyricListSearch.filter(
            oldWidget.document,
            oldWidget.visibleIndices,
            _searchQuery,
          ),
          _filteredIndices,
        );
    if (widget.filter == LyricReviewFilter.needsReview &&
        (oldWidget.filter != widget.filter ||
            visibleIndicesChanged ||
            searchChanged)) {
      _scheduleScrollToTop();
    } else if (widget.filter != LyricReviewFilter.needsReview &&
        widget.followPlayback &&
        (!oldWidget.followPlayback ||
            oldWidget.currentPlaybackLine != widget.currentPlaybackLine ||
            visibleIndicesChanged)) {
      _scheduleFollow();
    }
  }

  void _scheduleInsertedLineFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.focusLineIndex;
      if (index != null) widget.onInsertedLineFocus(index);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset < 1) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.followPlayback ||
          widget.filter == LyricReviewFilter.needsReview ||
          !_scrollController.hasClients) {
        return;
      }
      final current = widget.currentPlaybackLine;
      if (current == null) return;
      final position = _scrollController.position;
      final target = LyricListNavigation.followTarget(
        position: _filteredIndices.indexOf(current),
        viewport: position.viewportDimension,
        minExtent: position.minScrollExtent,
        maxExtent: position.maxScrollExtent,
        offset: _scrollController.offset,
      );
      if (target == null) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _startInlineEdit(int index) {
    setState(() => _editingIndex = index);
    widget.onSelectLine(index);
  }

  void _cancelInlineEdit() {
    setState(() => _editingIndex = null);
  }

  void _saveInlineEdit(int index, String newText) {
    final document = widget.document;
    if (index >= 0 &&
        index < document.lines.length &&
        newText.trim() != document.lines[index].text) {
      final line = document.lines[index];
      widget.onUpdateLine(index, line.copyWith(text: newText, confidence: 100));
    }
    setState(() => _editingIndex = null);
  }

  Future<void> _editTime(int index, {required bool start}) async {
    if (index < 0 || index >= widget.document.lines.length) return;
    final edited = await editLyricLineTime(
      context,
      widget.document.lines[index],
      start: start,
    );
    if (edited == null || !mounted) return;
    widget.onUpdateLine(index, edited);
  }

  void _copyLine(int index, LyricLine line) {
    Clipboard.setData(ClipboardData(text: line.text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制：第 ${index + 1} 行')));
  }

  void _setSearch(String value) => setState(() => _searchQuery = value);

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  /// Runs the key's command and says whether the key was used. Keys the list
  /// does not use go on to the app, so Tab still moves focus out of the list
  /// and the global playback shortcuts still work while it has focus.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _editingIndex != null) return false;
    final keyboard = HardwareKeyboard.instance;
    final command = LyricListNavigation.commandFor(
      event.logicalKey,
      command: keyboard.isControlPressed || keyboard.isMetaPressed,
    );
    if (command == null) return false;
    if (command == LyricListCommand.search) {
      if (!_showsSearch) return false;
      _searchFocusNode.requestFocus();
      return true;
    }
    final selected = widget.selectedIndex;
    if (selected == null) return false;
    switch (command) {
      case LyricListCommand.next:
        final next = LyricListNavigation.next(_filteredIndices, selected);
        if (next != null) widget.onSelectLine(next);
      case LyricListCommand.previous:
        final previous = LyricListNavigation.previous(
          _filteredIndices,
          selected,
        );
        if (previous != null) widget.onSelectLine(previous);
      case LyricListCommand.edit:
        _startInlineEdit(selected);
      case LyricListCommand.delete:
        widget.onDeleteLine(selected);
      case LyricListCommand.search:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.isCompact
        ? 8.0
        : spec.pageGutter.clamp(12, 24).toDouble();

    final filtered = _filteredIndices;
    // Worked out once per build: asking per row re-read every decision for
    // every row on screen.
    final reviewed = const LyricReviewDecisionService().reviewedIndices(
      widget.document,
    );
    final highlights = LyricCandidateHighlights.from(
      widget.document,
      reviewed: reviewed,
    );
    final summary = highlights == null || !highlights.hasSummary
        ? null
        : LyricCandidateSummary(
            text: highlights.summary(filtered),
            padding: padding,
          );
    final searchField = LyricListSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      query: _searchQuery,
      onChanged: _setSearch,
      onClear: _clearSearch,
      padding: padding,
    );

    if (widget.visibleIndices.isEmpty) {
      final empty = widget.filter == LyricReviewFilter.needsReview
          ? LyricReviewQueueEmptyState(
              reviewedCount: reviewed.length,
              onShowAllLines: widget.onShowAllLines,
            )
          : LyricFilteredEmptyState(onShowAllLines: widget.onShowAllLines);
      if (summary == null) return empty;
      return Column(
        children: [
          summary,
          Expanded(child: empty),
        ],
      );
    }

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          ?summary,
          searchField,
          const Expanded(child: LyricSearchEmptyState()),
        ],
      );
    }

    return Focus(
      focusNode: _listFocusNode,
      onKeyEvent: (node, event) => _handleKeyEvent(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: Column(
        children: [
          ?summary,
          if (_showsSearch) searchField,
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
              itemCount: filtered.length,
              itemBuilder: (context, visibleIndex) => _buildRow(
                filtered[visibleIndex],
                reviewed: reviewed,
                highlights: highlights,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    int index, {
    required Set<int> reviewed,
    required LyricCandidateHighlights? highlights,
  }) {
    final line = widget.document.lines[index];
    if (_editingIndex == index) {
      return InlineLyricEditorRow(
        key: ValueKey('inline_edit_$index'),
        index: index,
        line: line,
        onSave: (text) => _saveInlineEdit(index, text),
        onCancel: _cancelInlineEdit,
        onEditStartTime: () => _editTime(index, start: true),
        onEditEndTime: () => _editTime(index, start: false),
      );
    }
    final onPreview = widget.onPreviewLine;
    final onSplit = widget.onSplitLine;
    final onMerge = widget.onMergeLineWithNext;
    final onStart = widget.onSetStartFromPlayback;
    final onEnd = widget.onSetEndFromPlayback;
    final hasNext = index + 1 < widget.document.lines.length;
    return LyricReviewRow(
      index: index,
      line: line,
      fallbackCandidate: highlights?.shows(index) ?? true
          ? widget.fallbackCandidateFor(index)
          : null,
      isReviewed: reviewed.contains(index),
      isSecondarySuggestion: widget.secondarySuggestionIndices.contains(index),
      priority: widget.review.priorityByIndex[index],
      selected: widget.selectedIndex == index,
      playing: widget.currentPlaybackLine == index,
      hasAudio: onPreview != null,
      auditionIsPlaying:
          widget.auditionPlaying && widget.activeAuditionLineIndex == index,
      onPreview: onPreview == null ? null : () => onPreview(index),
      onTap: () {
        widget.onSelectLine(index);
        _listFocusNode.requestFocus();
      },
      onDoubleTap: () => _startInlineEdit(index),
      onLongPress: () => _startInlineEdit(index),
      onDelete: () => widget.onDeleteLine(index),
      onSplit: onSplit == null ? null : () => onSplit(index, null),
      onMergeWithNext: onMerge == null || !hasNext
          ? null
          : () => onMerge(index),
      onCopy: () => _copyLine(index, line),
      onEditStartTime: () => _editTime(index, start: true),
      onEditEndTime: () => _editTime(index, start: false),
      onSetStartFromPlayback: onStart == null ? null : () => onStart(index),
      onSetEndFromPlayback: onEnd == null ? null : () => onEnd(index),
      isManuallyEdited: widget.manuallyEditedLineIndices.contains(index),
    );
  }
}
