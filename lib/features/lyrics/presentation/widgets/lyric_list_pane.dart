import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_editor_toolbar.dart';
import 'lyric_row_audition_button.dart';

/// The editor's scrolling line list: one row per lyric line, in either editable
/// or review mode.
///
/// Extracted from the editor screen (Phase 4.1) with its parameters unchanged
/// so the behaviour stayed byte-for-byte while it became testable on its own.

class LyricListPane extends StatefulWidget {
  final LyricDocument document;
  final List<int> visibleIndices;
  final Map<int, LyricReviewPriority> reviewPriorityByIndex;
  final LyricReviewFilter filter;
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;
  final int? selectedIndex;
  final int? currentPlaybackLine;
  final bool followPlayback;
  final int focusRequestId;
  final int? focusLineIndex;
  final Map<String, dynamic>? Function(int) fallbackCandidateFor;
  final ValueChanged<int>? onPreviewLine;
  final ValueChanged<int> onInsertedLineFocus;
  final ValueChanged<int> onSelectLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<int>? onSetStartFromPlayback;
  final ValueChanged<int>? onSetEndFromPlayback;
  final Set<int> manuallyEditedLineIndices;

  const LyricListPane({
    required this.document,
    required this.visibleIndices,
    required this.reviewPriorityByIndex,
    required this.filter,
    required this.activeAuditionLineIndex,
    required this.auditionPlaying,
    required this.selectedIndex,
    required this.currentPlaybackLine,
    required this.followPlayback,
    required this.focusRequestId,
    required this.focusLineIndex,
    required this.fallbackCandidateFor,
    required this.onPreviewLine,
    required this.onInsertedLineFocus,
    required this.onSelectLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    this.onSetStartFromPlayback,
    this.onSetEndFromPlayback,
    this.manuallyEditedLineIndices = const {},
  });

  @override
  State<LyricListPane> createState() => _LyricListPaneState();
}

class _LyricListPaneState extends State<LyricListPane> {
  static const double _estimatedRowExtent = 68;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _listFocusNode = FocusNode();

  int? _editingIndex;
  String _searchQuery = '';

  List<int> get _filteredIndices {
    if (_searchQuery.trim().isEmpty) return widget.visibleIndices;
    final query = _searchQuery.trim().toLowerCase();
    return widget.visibleIndices.where((index) {
      final line = widget.document.lines[index];
      return line.text.toLowerCase().contains(query) ||
          formatLyricDuration(line.startTime).contains(query) ||
          '${index + 1}'.contains(query);
    }).toList();
  }

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
    if (oldWidget.document.lines.length != widget.document.lines.length) {
      if (_editingIndex != null &&
          (_editingIndex! < 0 ||
              _editingIndex! >= widget.document.lines.length)) {
        _editingIndex = null;
      }
    }
    final visibleIndicesChanged = !_sameIndices(
      oldWidget.visibleIndices,
      widget.visibleIndices,
    );
    final searchChanged =
        _searchQuery.isNotEmpty &&
        !_sameIndices(
          oldWidget.visibleIndices.where((i) {
            final q = _searchQuery.trim().toLowerCase();
            return widget.document.lines[i].text.toLowerCase().contains(q);
          }).toList(),
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

  bool _sameIndices(List<int> left, List<int> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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
      final visiblePosition = _filteredIndices.indexOf(current);
      if (visiblePosition < 0) return;
      final position = _scrollController.position;
      final rawTarget =
          visiblePosition * _estimatedRowExtent -
          position.viewportDimension * 0.42;
      final target = rawTarget
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_scrollController.offset - target).abs() < 20) return;
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
    if (index < 0 || index >= document.lines.length) {
      setState(() => _editingIndex = null);
      return;
    }
    final line = document.lines[index];
    if (newText.trim() == line.text) {
      setState(() => _editingIndex = null);
      return;
    }
    widget.onUpdateLine(index, line.copyWith(text: newText, confidence: 100));
    setState(() => _editingIndex = null);
  }

  Future<void> _editStartTime(int index) async {
    if (index < 0 || index >= widget.document.lines.length) return;
    final line = widget.document.lines[index];
    final result = await showDialog<Duration>(
      context: context,
      builder: (_) => TimestampEditDialog(
        title: '编辑开始时间',
        initial: line.startTime,
        label: '开始时间',
      ),
    );
    if (result == null || !mounted) return;
    if (result > line.endTime - const Duration(milliseconds: 10)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开始时间不能晚于结束时间')));
      return;
    }
    widget.onUpdateLine(index, line.copyWith(startTime: result));
  }

  Future<void> _editEndTime(int index) async {
    if (index < 0 || index >= widget.document.lines.length) return;
    final line = widget.document.lines[index];
    final result = await showDialog<Duration>(
      context: context,
      builder: (_) => TimestampEditDialog(
        title: '编辑结束时间',
        initial: line.endTime,
        label: '结束时间',
      ),
    );
    if (result == null || !mounted) return;
    if (result < line.startTime + const Duration(milliseconds: 10)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
      return;
    }
    widget.onUpdateLine(index, line.copyWith(endTime: result));
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_editingIndex != null) return;
    final selected = widget.selectedIndex;
    if (selected == null) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final pos = _filteredIndices.indexOf(selected);
      if (pos >= 0 && pos + 1 < _filteredIndices.length) {
        widget.onSelectLine(_filteredIndices[pos + 1]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final pos = _filteredIndices.indexOf(selected);
      if (pos > 0) {
        widget.onSelectLine(_filteredIndices[pos - 1]);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _startInlineEdit(selected);
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        widget.onDeleteLine(selected);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed) {
      // Ctrl/Cmd+F focuses search – handled by search field focus
    } else if (event.logicalKey == LogicalKeyboardKey.f2) {
      _startInlineEdit(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleIndices.isEmpty) {
      if (widget.filter == LyricReviewFilter.needsReview) {
        return _ReviewQueueEmptyState(
          reviewedCount: const LyricReviewDecisionService()
              .reviewedIndices(widget.document)
              .length,
        );
      }
      return const _FilteredEmptyState();
    }

    final spec = AppResponsive.of(context);
    final padding = spec.isCompact
        ? 8.0
        : spec.pageGutter.clamp(12, 24).toDouble();

    final filtered = _filteredIndices;

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Column(
        children: [
          _buildSearchBar(spec, padding),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 42,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(height: 8),
                  Text('没有匹配的歌词行'),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Focus(
      focusNode: _listFocusNode,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Column(
        children: [
          if (widget.document.lines.length > 8) _buildSearchBar(spec, padding),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
              itemCount: filtered.length,
              itemBuilder: (context, visibleIndex) {
                final index = filtered[visibleIndex];
                final line = widget.document.lines[index];
                final candidate = widget.fallbackCandidateFor(index);
                final isEditing = _editingIndex == index;
                if (isEditing) {
                  return InlineLyricEditorRow(
                    key: ValueKey('inline_edit_$index'),
                    index: index,
                    line: line,
                    onSave: (text) => _saveInlineEdit(index, text),
                    onCancel: _cancelInlineEdit,
                    onEditStartTime: () => _editStartTime(index),
                    onEditEndTime: () => _editEndTime(index),
                  );
                }
                return LyricReviewRow(
                  index: index,
                  line: line,
                  fallbackCandidate: candidate,
                  isReviewed: const LyricReviewDecisionService().isReviewed(
                    widget.document,
                    index,
                  ),
                  priority: widget.reviewPriorityByIndex[index],
                  selected: widget.selectedIndex == index,
                  playing: widget.currentPlaybackLine == index,
                  hasAudio: widget.onPreviewLine != null,
                  auditionIsPlaying:
                      widget.auditionPlaying &&
                      widget.activeAuditionLineIndex == index,
                  onPreview: widget.onPreviewLine == null
                      ? null
                      : () => widget.onPreviewLine!(index),
                  onTap: () {
                    widget.onSelectLine(index);
                    _listFocusNode.requestFocus();
                  },
                  onDoubleTap: () => _startInlineEdit(index),
                  onLongPress: () => _startInlineEdit(index),
                  onDelete: () => widget.onDeleteLine(index),
                  onCopy: () {
                    final text = line.text;
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已复制：第 ${index + 1} 行')),
                    );
                  },
                  onEditStartTime: () => _editStartTime(index),
                  onEditEndTime: () => _editEndTime(index),
                  onSetStartFromPlayback: widget.onSetStartFromPlayback == null
                      ? null
                      : () => widget.onSetStartFromPlayback!(index),
                  onSetEndFromPlayback: widget.onSetEndFromPlayback == null
                      ? null
                      : () => widget.onSetEndFromPlayback!(index),
                  isManuallyEdited: widget.manuallyEditedLineIndices.contains(
                    index,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLayoutSpec spec, double padding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: '搜索歌词文本、时间或行号…',
          hintStyle: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          filled: true,
          fillColor: AppColors.bgSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class InlineLyricEditorRow extends StatefulWidget {
  final int index;
  final LyricLine line;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;
  final VoidCallback onEditStartTime;
  final VoidCallback onEditEndTime;

  const InlineLyricEditorRow({
    super.key,
    required this.index,
    required this.line,
    required this.onSave,
    required this.onCancel,
    required this.onEditStartTime,
    required this.onEditEndTime,
  });

  @override
  State<InlineLyricEditorRow> createState() => _InlineLyricEditorRowState();
}

class _InlineLyricEditorRowState extends State<InlineLyricEditorRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.line.text);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void didUpdateWidget(covariant InlineLyricEditorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.text != widget.line.text &&
        _controller.text != widget.line.text) {
      _controller.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSave(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            border: Border.all(color: AppColors.accent.withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: spec.isCompact ? 28 : 34,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.index + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onEditStartTime,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        formatLyricDuration(widget.line.startTime),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    ' → ',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                  InkWell(
                    onTap: widget.onEditEndTime,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        formatLyricDuration(widget.line.endTime),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '按回车保存 · Esc 取消',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.onCancel();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: '输入歌词文本',
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('取消'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          spec.minimumInteractiveExtent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('保存'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          spec.minimumInteractiveExtent,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimestampEditDialog extends StatefulWidget {
  final String title;
  final Duration initial;
  final String label;

  const TimestampEditDialog({
    required this.title,
    required this.initial,
    required this.label,
  });

  @override
  State<TimestampEditDialog> createState() => _TimestampEditDialogState();
}

class _TimestampEditDialogState extends State<TimestampEditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatLyricDuration(widget.initial),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration? _parseTimestamp(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // Accept mm:ss.hh, m:ss.hh, mm:ss, mm:ss:hh, or raw seconds
    final regex = RegExp(r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$');
    final match = regex.firstMatch(trimmed);
    if (match != null) {
      final minutes = int.tryParse(match.group(1)!);
      final seconds = int.tryParse(match.group(2)!);
      final fractionStr = match.group(3);
      if (minutes == null || seconds == null || seconds >= 60) return null;
      var millis = 0;
      if (fractionStr != null) {
        final padded = (fractionStr + '000').substring(0, 3);
        millis = int.tryParse(padded) ?? 0;
        // If original was 2-digit centiseconds, correct
        if (fractionStr.length == 2) {
          millis = int.tryParse(fractionStr)! * 10;
        } else if (fractionStr.length == 1) {
          millis = int.tryParse(fractionStr)! * 100;
        }
      }
      return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
    }
    // Try plain seconds like "83.5"
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null && asDouble >= 0) {
      return Duration(milliseconds: (asDouble * 1000).round());
    }
    return null;
  }

  void _submit() {
    final parsed = _parseTimestamp(_controller.text);
    if (parsed == null) {
      setState(() => _error = '格式应为 mm:ss.hh，例如 01:23.45');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'mm:ss.hh，例如 01:23.45',
              helperText: '也支持 83.5（秒）',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前：${formatLyricDuration(widget.initial)}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

class LyricReviewRow extends StatelessWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final LyricReviewPriority? priority;
  final bool selected;
  final bool playing;
  final bool hasAudio;
  final bool auditionIsPlaying;
  final VoidCallback? onPreview;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onEditStartTime;
  final VoidCallback? onEditEndTime;
  final VoidCallback? onSetStartFromPlayback;
  final VoidCallback? onSetEndFromPlayback;
  final bool isManuallyEdited;

  const LyricReviewRow({
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.priority,
    required this.selected,
    required this.playing,
    required this.hasAudio,
    required this.auditionIsPlaying,
    required this.onPreview,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onDelete,
    this.onCopy,
    this.onEditStartTime,
    this.onEditEndTime,
    this.onSetStartFromPlayback,
    this.onSetEndFromPlayback,
    this.isManuallyEdited = false,
  });

  void _showContextMenu(BuildContext context, Offset position) {
    final entries = <PopupMenuEntry<String>>[
      if (onDoubleTap != null)
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_rounded, size: 18),
            title: Text('编辑文字（双击）'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (onEditStartTime != null)
        const PopupMenuItem(
          value: 'editStart',
          child: ListTile(
            leading: Icon(Icons.timer_outlined, size: 18),
            title: Text('编辑开始时间'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (onEditEndTime != null)
        const PopupMenuItem(
          value: 'editEnd',
          child: ListTile(
            leading: Icon(Icons.timer_outlined, size: 18),
            title: Text('编辑结束时间'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (onSetStartFromPlayback != null)
        const PopupMenuItem(
          value: 'markStart',
          child: ListTile(
            leading: Icon(Icons.my_location_rounded, size: 18),
            title: Text('标记人声起点为当前播放'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (onSetEndFromPlayback != null)
        const PopupMenuItem(
          value: 'markEnd',
          child: ListTile(
            leading: Icon(Icons.my_location_rounded, size: 18),
            title: Text('标记人声终点为当前播放'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (onDelete != null)
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.error,
            ),
            title: Text('删除此行', style: TextStyle(color: AppColors.error)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
    if (entries.isEmpty) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: entries,
    ).then((value) {
      switch (value) {
        case 'edit':
          onDoubleTap?.call();
          break;
        case 'editStart':
          onEditStartTime?.call();
          break;
        case 'editEnd':
          onEditEndTime?.call();
          break;
        case 'markStart':
          onSetStartFromPlayback?.call();
          break;
        case 'markEnd':
          onSetEndFromPlayback?.call();
          break;
        case 'delete':
          onDelete?.call();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final background = selected
        ? AppColors.bgSurface
        : playing
        ? AppColors.accent.withAlpha(18)
        : Colors.transparent;

    final isLongText = line.text.runes.length > 28;
    final displayText = line.text.trim().isEmpty ? '（空歌词）' : line.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: onLongPress,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: Tooltip(
            message: onDoubleTap == null ? null : '双击直接编辑文字 · 右键更多操作',
            child: Container(
              constraints: BoxConstraints(
                minHeight: spec.minimumInteractiveExtent,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                border: selected
                    ? Border.all(color: AppColors.accent.withAlpha(120))
                    : null,
              ),
              child: Row(
                crossAxisAlignment: isLongText && selected
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: spec.isCompact ? 28 : 34,
                    child: playing
                        ? const Icon(
                            Icons.graphic_eq_rounded,
                            size: 18,
                            color: AppColors.accent,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${index + 1}',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppColors.textTertiary),
                              ),
                              if (isManuallyEdited)
                                Container(
                                  margin: const EdgeInsets.only(left: 3),
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  LyricRowAuditionButton(
                    hasAudio: hasAudio,
                    isPlaying: auditionIsPlaying,
                    onPressed: onPreview,
                  ),
                  if (hasAudio) const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: '点击直接编辑时间',
                    child: InkWell(
                      onTap: onEditStartTime,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusSmall,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          formatLyricDuration(line.startTime),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textTertiary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                decoration: onEditStartTime != null
                                    ? TextDecoration.underline
                                    : null,
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '–',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.borderSubtle,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: '点击直接编辑时间',
                    child: InkWell(
                      onTap: onEditEndTime,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusSmall,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          formatLyricDuration(line.endTime),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textTertiary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                decoration: onEditEndTime != null
                                    ? TextDecoration.underline
                                    : null,
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: selected && isLongText
                        ? Text(
                            displayText,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: line.text.trim().isEmpty
                                      ? AppColors.textTertiary
                                      : AppColors.textPrimary,
                                  fontWeight: playing
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          )
                        : Text(
                            displayText,
                            maxLines: spec.isCompact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: line.text.trim().isEmpty
                                      ? AppColors.textTertiary
                                      : AppColors.textPrimary,
                                  fontWeight: playing
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontStyle: isManuallyEdited
                                      ? FontStyle.italic
                                      : null,
                                ),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (!spec.isCompact && line.isChorus)
                    const LyricTinyBadge(label: '副歌', accent: true),
                  if (!spec.isCompact &&
                      fallbackCandidate != null &&
                      line.confidence < 100) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const LyricTinyBadge(label: '双引擎'),
                  ],
                  if (isReviewed) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const LyricTinyBadge(label: '已复核', accent: true),
                  ] else if (priority != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Tooltip(
                      message: priority!.reasons.join('\n'),
                      child: LyricTinyBadge(
                        label: spec.isCompact ? '复核' : '优先 ${priority!.score}',
                        warning: priority!.score >= 45,
                      ),
                    ),
                  ],
                  if (selected && onDoubleTap != null && !spec.isCompact) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Tooltip(
                      message: '双击或按 F2 编辑',
                      child: Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.textTertiary.withAlpha(160),
                      ),
                    ),
                  ],
                  if (!spec.supportsTwoPane) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewQueueEmptyState extends StatelessWidget {
  final int reviewedCount;

  const _ReviewQueueEmptyState({required this.reviewedCount});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final completed = reviewedCount > 0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter.clamp(16, 32).toDouble()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 44,
                color: AppColors.accent,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                completed ? '本轮复核已完成' : '暂未发现明显风险行',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                completed
                    ? '已确认 $reviewedCount 行。若修改了歌词文本或时间轴，该行会自动重新进入待复核队列。请保存以保留确认记录。'
                    : '当前没有达到复核阈值的明显问题。自动排序只看结构与时间轴证据，不能判断歌词语义是否正确，仍可结合试听和个人听感检查。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_alt_rounded, size: 42, color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          Text('当前筛选下没有待处理歌词', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
