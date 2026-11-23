import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import 'lyric_batch_selection_bar.dart';
import 'lyric_editor_review_controls.dart';
import 'lyric_editor_toolbar.dart';
import 'lyric_inline_editor_row.dart';
import 'lyric_line_jump.dart';
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

  /// Choosing rows for a batch edit (D-066); null where batch edits are not
  /// offered, which keeps the long press on inline editing.
  final LyricBatchControls? batch;

  /// Requests to bring a row into view and flash it (跳到行, D-067).
  final LyricLineJumpController? jump;

  /// The button that ends a pause in following playback.
  static const resumeFollowKey = ValueKey('lyric_follow_resume');

  /// Its label, naming the row being sung.
  static String resumeFollowLabel(int index) => '回到正在播放的第 ${index + 1} 行';

  const LyricListPane({
    super.key,
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
    this.batch,
    this.jump,
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

  /// The rows on screen and the context each was built in, so a jump or an
  /// arrow key can measure where a row really is (rows differ in height).
  final Map<int, BuildContext> _rowContexts = {};

  /// The row a jump or an arrow key last asked to bring into view.
  int? _revealIndex;

  /// The row to flash for jump [_flashId], until it has started flashing.
  int? _flashIndex;
  int _flashId = 0;

  /// Following playback pauses while the person looks around the list
  /// themselves (D-067) and picks up [LyricListNavigation.followPause]
  /// after they stop.
  bool _followPaused = false;

  /// The playing row moved while following waited (paused, or a row being
  /// edited in place), so the list is not where following would put it.
  bool _followMissed = false;
  Timer? _followResumeTimer;

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
    widget.jump?.addListener(_onJump);
    _scheduleFollow();
    if (widget.focusRequestId > 0) {
      _scheduleInsertedLineFocus();
    }
  }

  @override
  void didUpdateWidget(covariant LyricListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jump != widget.jump) {
      oldWidget.jump?.removeListener(_onJump);
      widget.jump?.addListener(_onJump);
    }
    if (!widget.followPlayback && _followPaused) {
      _followResumeTimer?.cancel();
      _followResumeTimer = null;
      _followPaused = false;
      _followMissed = false;
    }
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
    if (widget.filter == LyricReviewFilter.suggested &&
        (oldWidget.filter != widget.filter ||
            visibleIndicesChanged ||
            searchChanged)) {
      _scheduleScrollToTop();
    } else if (widget.filter != LyricReviewFilter.suggested &&
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
    widget.jump?.removeListener(_onJump);
    _followResumeTimer?.cancel();
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
          widget.filter == LyricReviewFilter.suggested ||
          !_scrollController.hasClients) {
        return;
      }
      final current = widget.currentPlaybackLine;
      if (current == null) return;
      // Someone is reading or editing elsewhere in the list: remember that
      // the list fell behind instead of pulling it away from them.
      if (_followPaused || _editingIndex != null) {
        if (!_followMissed) setState(() => _followMissed = true);
        return;
      }
      if (!_filteredIndices.contains(current)) return;
      final target = _measuredOffset(current, LyricListNavigation.followAnchor);
      if (target == null) {
        // Far away and not built yet: estimate, then measure (D-067).
        _revealIndex = current;
        _reveal(current, jump: true);
        return;
      }
      final offset = _scrollController.offset;
      if ((target - offset).abs() < LyricListNavigation.followSlack) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// The offset that puts built row [index] at [alignment] of the window
  /// (0 top, 1 bottom), within the scroll range; null while it is not
  /// built.
  double? _measuredOffset(int index, double alignment) {
    final row = _rowContexts[index]?.findRenderObject();
    if (row == null || !row.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (viewport == null) return null;
    final position = _scrollController.position;
    return viewport
        .getOffsetToReveal(row, alignment)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  /// Holds following back for [LyricListNavigation.followPause], counted
  /// again from every call.
  void _pauseFollow() {
    if (!widget.followPlayback) return;
    _followResumeTimer?.cancel();
    _followResumeTimer = Timer(
      LyricListNavigation.followPause,
      _endFollowPause,
    );
    if (!_followPaused) setState(() => _followPaused = true);
  }

  /// The pause ran out: catch up only when the playing row moved meanwhile,
  /// so looking around a paused song does not snap the list back.
  void _endFollowPause() {
    _followResumeTimer = null;
    if (!mounted) return;
    final missed = _followMissed;
    setState(() {
      _followPaused = false;
      _followMissed = false;
    });
    if (missed) _scheduleFollow();
  }

  /// 回到正在播放: follow again at once.
  void _resumeFollowNow() {
    _followResumeTimer?.cancel();
    _followResumeTimer = null;
    setState(() {
      _followPaused = false;
      _followMissed = false;
    });
    _scheduleFollow();
  }

  /// After editing in place, catch up with a playhead that moved meanwhile.
  void _catchUpFollow() {
    if (!_followMissed || _followPaused) return;
    _followMissed = false;
    _scheduleFollow();
  }

  /// Dragging, flinging, the mouse wheel and the scroll bar pause
  /// following; the list's own animated scrolls do not.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final manual = switch (notification) {
      UserScrollNotification(:final direction) =>
        direction != ScrollDirection.idle,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (manual) _pauseFollow();
    return false;
  }

  /// 跳到行: show the row, flash it and give the list the keyboard.
  void _onJump() {
    final target = widget.jump?.target;
    if (!mounted || target == null) return;
    final document = widget.document;
    if (target < 0 || target >= document.lines.length) return;
    final query = LyricListSearch.normalize(_searchQuery);
    final hiddenBySearch =
        query.isNotEmpty &&
        !LyricListSearch.matches(document.lines[target], target, query);
    if (hiddenBySearch) _searchController.clear();
    setState(() {
      if (hiddenBySearch) _searchQuery = '';
      _revealIndex = target;
      _flashIndex = target;
      _flashId++;
    });
    _pauseFollow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listFocusNode.context != null) _listFocusNode.requestFocus();
      _reveal(target, jump: true);
    });
  }

  /// Scrolls row [index] into view: a jump puts it where following puts
  /// the playing row, an arrow key only scrolls as far as needed. A row
  /// not built yet is first scrolled to by estimate, then measured.
  void _reveal(int index, {required bool jump, int attempt = 0}) {
    if (!mounted || !_scrollController.hasClients || _revealIndex != index) {
      return;
    }
    final position = _scrollController.position;
    final top = _measuredOffset(index, 0);
    if (top != null) {
      final double? target = jump
          ? _measuredOffset(index, LyricListNavigation.followAnchor)
          : LyricListNavigation.keepVisibleOffset(
              offset: position.pixels,
              top: top,
              bottom: _measuredOffset(index, 1)!,
              minExtent: position.minScrollExtent,
              maxExtent: position.maxScrollExtent,
            );
      if (target == null || (target - position.pixels).abs() < 1) return;
      _scrollController.animateTo(
        target,
        duration: Duration(milliseconds: jump ? 240 : 120),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (attempt >= LyricListNavigation.revealAttempts) return;
    final shown = _filteredIndices;
    final place = shown.indexOf(index);
    if (place < 0) return;
    _scrollController.jumpTo(
      LyricListNavigation.revealEstimate(
        position: place,
        rowExtent: LyricListNavigation.averageRowExtent(
          maxExtent: position.maxScrollExtent,
          viewport: position.viewportDimension,
          rows: shown.length,
        ),
        viewport: position.viewportDimension,
        minExtent: position.minScrollExtent,
        maxExtent: position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(index, jump: jump, attempt: attempt + 1),
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  void _startInlineEdit(int index) {
    setState(() => _editingIndex = index);
    widget.onSelectLine(index);
  }

  void _cancelInlineEdit() {
    setState(() => _editingIndex = null);
    _catchUpFollow();
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
    _catchUpFollow();
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
    final batch = widget.batch;
    final command = LyricListNavigation.commandFor(
      event.logicalKey,
      command: keyboard.isControlPressed || keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      batch: batch?.active ?? false,
    );
    if (command == null) return false;
    switch (command) {
      case LyricListCommand.search:
        if (!_showsSearch) return false;
        _searchFocusNode.requestFocus();
        return true;
      case LyricListCommand.selectAll:
        if (batch == null) return false;
        batch.onSelectAll(_filteredIndices);
        return true;
      case LyricListCommand.endBatch:
        if (batch == null) return false;
        batch.onEnd();
        return true;
      default:
        break;
    }
    final selected = widget.selectedIndex;
    if (selected == null) return false;
    final shown = _filteredIndices;
    switch (command) {
      case LyricListCommand.next:
      case LyricListCommand.extendNext:
        final next = LyricListNavigation.next(shown, selected);
        if (next != null) _moveTo(next, extend: command.growsBatch);
      case LyricListCommand.previous:
      case LyricListCommand.extendPrevious:
        final previous = LyricListNavigation.previous(shown, selected);
        if (previous != null) _moveTo(previous, extend: command.growsBatch);
      case LyricListCommand.edit:
        _startInlineEdit(selected);
      case LyricListCommand.delete:
        if (batch != null && batch.active && batch.selected.isNotEmpty) {
          batch.onDelete();
        } else {
          widget.onDeleteLine(selected);
        }
      case LyricListCommand.search:
      case LyricListCommand.selectAll:
      case LyricListCommand.endBatch:
        break;
    }
    return true;
  }

  /// Selects row [index]; with [extend] (Shift) the batch choice grows to it.
  /// The list scrolls along, and following playback waits meanwhile.
  void _moveTo(int index, {required bool extend}) {
    final batch = widget.batch;
    if (extend && batch != null) {
      batch.onRange(index, _filteredIndices);
    } else {
      widget.onSelectLine(index);
    }
    _pauseFollow();
    _revealIndex = index;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(index, jump: false),
    );
  }

  /// A tap on row [index]: Ctrl/Cmd adds it to the batch choice, Shift
  /// chooses up to it, and in batch mode a plain tap chooses it (D-066).
  void _tapRow(int index) {
    final batch = widget.batch;
    final keyboard = HardwareKeyboard.instance;
    if (batch != null &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      batch.onToggle(index, includeCurrent: true);
    } else if (batch != null && keyboard.isShiftPressed) {
      batch.onRange(index, _filteredIndices);
    } else if (batch != null && batch.active) {
      batch.onToggle(index);
    } else {
      widget.onSelectLine(index);
    }
    _listFocusNode.requestFocus();
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
      final empty = widget.filter == LyricReviewFilter.suggested
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
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                    itemCount: filtered.length,
                    itemBuilder: (context, visibleIndex) {
                      final index = filtered[visibleIndex];
                      return _ListRowFrame(
                        index: index,
                        contexts: _rowContexts,
                        flashId: index == _flashIndex ? _flashId : null,
                        onFlashStarted: () => _flashIndex = null,
                        child: _buildRow(
                          index,
                          reviewed: reviewed,
                          highlights: highlights,
                        ),
                      );
                    },
                  ),
                ),
                if (_resumeFollowRow(filtered) case final current?)
                  Positioned(
                    left: padding,
                    right: padding,
                    bottom: AppSpacing.md,
                    child: Center(
                      child: FilledButton.tonalIcon(
                        key: LyricListPane.resumeFollowKey,
                        onPressed: _resumeFollowNow,
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(LyricListPane.resumeFollowLabel(current)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The playing row while following waits and the list fell behind it;
  /// the 回到正在播放 button shows only then.
  int? _resumeFollowRow(List<int> shown) {
    final current = widget.currentPlaybackLine;
    if (!_followPaused ||
        !_followMissed ||
        !widget.followPlayback ||
        widget.filter == LyricReviewFilter.suggested ||
        current == null ||
        !shown.contains(current)) {
      return null;
    }
    return current;
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
    final batch = widget.batch;
    final choosing = batch != null && batch.active;
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
      onTap: () => _tapRow(index),
      // While choosing, a tap answers at once instead of waiting to see
      // whether a second tap follows.
      onDoubleTap: choosing ? null : () => _startInlineEdit(index),
      onLongPress: batch == null
          ? () => _startInlineEdit(index)
          : () => batch.onToggle(index),
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
      checked: choosing ? batch.isChosen(index) : null,
    );
  }
}

/// Wraps every row of the list the same way, so nothing inside a row is
/// rebuilt from scratch when a jump picks it out: it records the row's
/// context for measuring and flashes the row a jump landed on.
class _ListRowFrame extends StatefulWidget {
  const _ListRowFrame({
    required this.index,
    required this.contexts,
    required this.flashId,
    required this.onFlashStarted,
    required this.child,
  });

  final int index;
  final Map<int, BuildContext> contexts;

  /// The jump to flash for, or null.
  final int? flashId;
  final VoidCallback onFlashStarted;
  final Widget child;

  @override
  State<_ListRowFrame> createState() => _ListRowFrameState();
}

class _ListRowFrameState extends State<_ListRowFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: LyricListNavigation.jumpFlash,
  );

  @override
  void initState() {
    super.initState();
    widget.contexts[widget.index] = context;
    _startFlash();
  }

  @override
  void didUpdateWidget(covariant _ListRowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        !identical(oldWidget.contexts, widget.contexts)) {
      _forget(oldWidget);
      widget.contexts[widget.index] = context;
    }
    if (widget.flashId != oldWidget.flashId) _startFlash();
  }

  void _startFlash() {
    if (widget.flashId == null) return;
    _flash.forward(from: 0);
    widget.onFlashStarted();
  }

  void _forget(_ListRowFrame frame) {
    if (identical(frame.contexts[frame.index], context)) {
      frame.contexts.remove(frame.index);
    }
  }

  @override
  void dispose() {
    _forget(widget);
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final strength = _flash.isAnimating
            ? 1 - Curves.easeInCubic.transform(_flash.value)
            : 0.0;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: AppColors.accent.withAlpha((strength * 56).round()),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
