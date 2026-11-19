import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/models/secondary_only_suggestion.dart';
import '../../domain/services/character_diff_service.dart';
import 'lyric_editor_atoms.dart';
import 'lyric_word_timing_strip.dart';

/// Right-hand inspector for the selected line: timestamps, confidence, nudges
/// and alternative candidates.
///
/// Extracted from the editor screen (Phase 4.1); its parameters are unchanged.

class InspectorPane extends StatelessWidget {
  final LyricDocument document;
  final int? selectedIndex;
  final Map<String, dynamic>? fallbackCandidate;
  final SecondaryOnlySuggestion? secondarySuggestion;
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int? currentPlaybackLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;

  /// Splits a row at a text offset; null offset means the natural break.
  final void Function(int index, int? textOffset)? onSplitLine;

  /// Merges a row with the next one.
  final ValueChanged<int>? onMergeLineWithNext;
  final ValueChanged<int> onPreviewLine;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;

  /// Seeks the project's audio to an audio position (word timing chips).
  final ValueChanged<Duration>? onSeekPlayback;

  /// Opens word timing fine-tuning for the selected row.
  final VoidCallback? onEditWordTiming;
  final bool autofocusText;
  final int focusRequestId;

  const InspectorPane({
    required this.document,
    required this.selectedIndex,
    required this.fallbackCandidate,
    this.secondarySuggestion,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.currentPlaybackLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    this.onSplitLine,
    this.onMergeLineWithNext,
    required this.onPreviewLine,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
    this.onSeekPlayback,
    this.onEditWordTiming,
    required this.autofocusText,
    required this.focusRequestId,
  });

  @override
  Widget build(BuildContext context) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= document.lines.length) {
      return const NoSelectionInspector();
    }

    final line = document.lines[index];
    return LineInspector(
      key: ValueKey('inspector_${index}_$focusRequestId'),
      index: index,
      line: line,
      fallbackCandidate: fallbackCandidate,
      secondarySuggestion: secondarySuggestion,
      isReviewed: isReviewed,
      onReviewDecision: onReviewDecision,
      isCurrentPlaybackLine:
          playbackBelongsToProject && currentPlaybackLine == index,
      isPlaying: playbackBelongsToProject && playback.isPlaying,
      autofocusText: autofocusText,
      onUpdate: (updated) => onUpdateLine(index, updated),
      onDelete: () => onDeleteLine(index),
      onSplit: onSplitLine == null
          ? null
          : (textOffset) => onSplitLine!(index, textOffset),
      onMergeWithNext:
          onMergeLineWithNext == null || index + 1 >= document.lines.length
          ? null
          : () => onMergeLineWithNext!(index),
      onPreview: () => onPreviewLine(index),
      onUsePlaybackAsStart: playbackBelongsToProject
          ? () => onSetStartFromPlayback(index)
          : null,
      onUsePlaybackAsEnd: playbackBelongsToProject
          ? () => onSetEndFromPlayback(index)
          : null,
      onSeekToTime: playbackBelongsToProject && onSeekPlayback != null
          ? (time) =>
                onSeekPlayback!(time + (document.globalOffset ?? Duration.zero))
          : null,
      onEditWordTiming: onEditWordTiming,
    );
  }
}

class LineInspector extends StatefulWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;

  /// Set when only the secondary engine heard this row ("建议补入").
  final SecondaryOnlySuggestion? secondarySuggestion;
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final bool isCurrentPlaybackLine;
  final bool isPlaying;
  final bool autofocusText;
  final ValueChanged<LyricLine> onUpdate;
  final VoidCallback onDelete;

  /// Splits this row. The argument is the text cursor offset when the cursor
  /// sits inside the text, otherwise null (split at the natural break).
  final ValueChanged<int?>? onSplit;

  /// Merges this row with the next one; null on the last row.
  final VoidCallback? onMergeWithNext;
  final VoidCallback onPreview;
  final VoidCallback? onUsePlaybackAsStart;
  final VoidCallback? onUsePlaybackAsEnd;

  /// Seeks the project's audio to a time on the lyric timeline (the caller
  /// adds the global offset); null when this project is not loaded.
  final ValueChanged<Duration>? onSeekToTime;

  /// Opens word timing fine-tuning (逐字微调) for this row; null hides it.
  final VoidCallback? onEditWordTiming;

  /// Drives the inspector's scroll view; the narrow-screen sheet passes its
  /// drag controller so pulling the list down at the top resizes the sheet.
  final ScrollController? scrollController;

  const LineInspector({
    super.key,
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    this.secondarySuggestion,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.isCurrentPlaybackLine,
    required this.isPlaying,
    this.autofocusText = false,
    required this.onUpdate,
    required this.onDelete,
    this.onSplit,
    this.onMergeWithNext,
    required this.onPreview,
    this.onUsePlaybackAsStart,
    this.onUsePlaybackAsEnd,
    this.onSeekToTime,
    this.onEditWordTiming,
    this.scrollController,
  });

  @override
  State<LineInspector> createState() => _LineInspectorState();
}

class _LineInspectorState extends State<LineInspector> {
  late final TextEditingController _textController;
  late final FocusNode _textFocusNode;
  late LyricLine _workingLine;

  @override
  void initState() {
    super.initState();
    _workingLine = widget.line;
    _textController = TextEditingController(text: widget.line.text);
    _textFocusNode = FocusNode();
    if (widget.autofocusText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant LineInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _workingLine = widget.line;
    }
    if (oldWidget.line.text != widget.line.text &&
        _textController.text != widget.line.text) {
      _textController.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  String? _alternativeText() {
    final candidate = widget.fallbackCandidate;
    if (candidate == null) return null;
    final explicit = candidate['alternativeText'];
    if (explicit is String) return explicit;
    // The legacy Qwen-primary format stored Whisper's text under whisperText.
    // Never mistake a Whisper-primary record's own text for an alternative.
    final legacy = switch (candidate['primaryEngine']) {
      'qwen' => candidate['whisperText'],
      'whisper' => candidate['qwenText'],
      null
          when candidate['qwenText'] is String &&
              candidate['whisperText'] is String =>
        candidate['whisperText'],
      _ => null,
    };
    return legacy is String ? legacy : null;
  }

  String? _primaryText() {
    final candidate = widget.fallbackCandidate;
    if (candidate == null) return null;
    final primary = candidate['primaryText'];
    if (primary is String && primary.trim().isNotEmpty) return primary;
    final key = switch (candidate['primaryEngine']) {
      'whisper' => 'whisperText',
      'qwen' => 'qwenText',
      // Older Qwen-primary records did not include primaryEngine.
      null
          when candidate['qwenText'] is String &&
              candidate['whisperText'] is String =>
        'qwenText',
      _ => null,
    };
    final legacy = key == null ? null : candidate[key];
    return legacy is String && legacy.trim().isNotEmpty ? legacy : null;
  }

  String _engineLabel(String? engine) {
    return switch (engine) {
      'qwen' => 'Qwen',
      'whisper' => 'Whisper',
      _ => engine ?? '备用引擎',
    };
  }

  String _alternativeEngineLabel() {
    final candidate = widget.fallbackCandidate!;
    final named = candidate['alternativeEngine'];
    if (named is String && named.isNotEmpty) return _engineLabel(named);
    final primary = candidate['primaryEngine'];
    if (primary == 'qwen' && candidate['whisperText'] is String) {
      return 'Whisper';
    }
    if (primary == 'whisper' && candidate['qwenText'] is String) return 'Qwen';
    if (primary == null &&
        candidate['qwenText'] is String &&
        candidate['whisperText'] is String) {
      return 'Whisper';
    }
    return '备用引擎';
  }

  void _emitUpdate(LyricLine updated) {
    setState(() => _workingLine = updated);
    widget.onUpdate(updated);
  }

  void _updateText(String text) {
    _emitUpdate(_workingLine.copyWith(text: text, confidence: 100));
  }

  void _nudgeStart(Duration delta) {
    var next = _workingLine.startTime + delta;
    if (next.isNegative) next = Duration.zero;
    final latest = _workingLine.endTime - const Duration(milliseconds: 10);
    if (next > latest) next = latest.isNegative ? Duration.zero : latest;
    _emitUpdate(_workingLine.copyWith(startTime: next));
  }

  void _nudgeEnd(Duration delta) {
    var next = _workingLine.endTime + delta;
    final earliest = _workingLine.startTime + const Duration(milliseconds: 10);
    if (next < earliest) next = earliest;
    _emitUpdate(_workingLine.copyWith(endTime: next));
  }

  /// The cursor offset when it sits strictly inside the text, else null.
  int? _cursorSplitOffset() {
    final selection = _textController.selection;
    final text = _textController.text;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final offset = selection.baseOffset;
    if (offset <= 0 || offset >= text.length) return null;
    return offset;
  }

  void _split() => widget.onSplit?.call(_cursorSplitOffset());

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _applyCandidate(String text) {
    if (text.trim().isEmpty) return;
    _textController.text = text;
    _emitUpdate(_workingLine.copyWith(text: text, confidence: 100));
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final alternative = _alternativeText();
    final duration = _workingLine.endTime - _workingLine.startTime;
    final inspectorPadding = spec.pageGutter.clamp(12, 24).toDouble();

    return Container(
      color: AppColors.bgElevated,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.all(inspectorPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${widget.index + 1} 行',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatLyricDuration(_workingLine.startTime)} → ${formatLyricDuration(_workingLine.endTime)} · ${formatCompactLyricDuration(duration)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: spec.minimumInteractiveExtent,
                height: spec.minimumInteractiveExtent,
                child: IconButton.filledTonal(
                  tooltip: '从这一行开始试听',
                  onPressed: widget.onPreview,
                  icon: Icon(
                    widget.isCurrentPlaybackLine && widget.isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (_workingLine.isLowConfidence(kLyricReviewConfidenceThreshold))
                LyricTinyBadge(
                  label: '低置信度 ${_workingLine.confidence}',
                  warning: true,
                )
              else if (!_workingLine.hasConfidenceScore)
                const LyricTinyBadge(label: '未评分')
              else
                LyricTinyBadge(label: '置信度 ${_workingLine.confidence}'),
              if (_workingLine.isChorus)
                const LyricTinyBadge(label: '副歌', accent: true),
              if (widget.fallbackCandidate != null)
                const LyricTinyBadge(label: '双引擎复核'),
              if (widget.secondarySuggestion != null && !widget.isReviewed)
                const LyricTinyBadge(label: '建议补入', warning: true),
            ],
          ),
          if (_workingLine.words.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            LyricWordTimingStrip(
              line: _workingLine,
              onSeek: widget.onSeekToTime,
              onClear: () =>
                  _emitUpdate(_workingLine.copyWith(words: const [])),
              onEdit: widget.onEditWordTiming,
            ),
          ] else if (widget.onEditWordTiming != null &&
              _workingLine.text.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('word_timing_edit_start'),
                onPressed: widget.onEditWordTiming,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('逐字微调（从估算开始）'),
              ),
            ),
          ],
          if (widget.secondarySuggestion != null && !widget.isReviewed) ...[
            const SizedBox(height: AppSpacing.md),
            SecondarySuggestionCard(
              suggestion: widget.secondarySuggestion!,
              onPreview: widget.onPreview,
              onKeep:
                  widget.onReviewDecision == null ||
                      widget.line.id?.isNotEmpty != true
                  ? null
                  : () => widget.onReviewDecision!(true),
              onReject: widget.onDelete,
            ),
          ],
          // A pending suggestion has its own keep/reject card below; one
          // decision button per row keeps the hierarchy calm.
          if (widget.onReviewDecision != null &&
              widget.line.id?.isNotEmpty == true &&
              !(widget.secondarySuggestion != null && !widget.isReviewed)) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => widget.onReviewDecision!(!widget.isReviewed),
                icon: Icon(
                  widget.isReviewed
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                ),
                label: Text(widget.isReviewed ? '取消已复核标记' : '确认歌词与时间无误并继续'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          CallbackShortcuts(
            // Ctrl/Cmd+Enter splits at the cursor without leaving the text.
            bindings: <ShortcutActivator, VoidCallback>{
              if (widget.onSplit != null)
                SingleActivator(
                  LogicalKeyboardKey.enter,
                  control: !_isApple,
                  meta: _isApple,
                ): _split,
            },
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              onChanged: _updateText,
              minLines: 2,
              maxLines: spec.isShort ? 3 : 4,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: InputDecoration(
                labelText: '歌词文本',
                hintText: '输入这一行歌词',
                filled: true,
                fillColor: AppColors.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (widget.onSplit != null || widget.onMergeWithNext != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LineStructureActions(
              onSplit: widget.onSplit == null ? null : _split,
              onMergeWithNext: widget.onMergeWithNext,
              splitShortcutLabel: _isApple ? '⌘↩' : 'Ctrl+Enter',
            ),
          ],
          if (!widget.isReviewed &&
              widget.fallbackCandidate != null &&
              alternative?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            AlternativeCandidateCard(
              primaryEngine: _engineLabel(
                widget.fallbackCandidate!['primaryEngine']?.toString() ??
                    (widget.fallbackCandidate!['primaryText'] == null &&
                            widget.fallbackCandidate!['qwenText'] is String
                        ? 'qwen'
                        : '主模型'),
              ),
              alternativeEngine: _alternativeEngineLabel(),
              primaryText: _primaryText(),
              currentText: _workingLine.text,
              alternativeText: alternative!,
              onApply:
                  widget.fallbackCandidate!['sharedSecondaryAcrossPrimaryLines'] ==
                      true
                  ? null
                  : () => _applyCandidate(alternative),
              sharedSecondary:
                  widget
                      .fallbackCandidate!['sharedSecondaryAcrossPrimaryLines'] ==
                  true,
              onApplyPrimary: _primaryText() == null
                  ? null
                  : () => _applyCandidate(_primaryText()!),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TimingEditor(
            title: '人声起点',
            playbackPositionLabel: '标记人声起点',
            value: _workingLine.startTime,
            onNudge: _nudgeStart,
            onUsePlaybackPosition: widget.onUsePlaybackAsStart,
          ),
          const SizedBox(height: AppSpacing.sm),
          TimingEditor(
            title: '人声终点',
            playbackPositionLabel: '标记人声终点',
            value: _workingLine.endTime,
            onNudge: _nudgeEnd,
            onUsePlaybackPosition: widget.onUsePlaybackAsEnd,
          ),
          const SizedBox(height: AppSpacing.lg),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('标记为副歌'),
              subtitle: const Text('播放器可使用这一标记强化副歌段落'),
              value: _workingLine.isChorus,
              onChanged: (value) =>
                  _emitUpdate(_workingLine.copyWith(isChorus: value)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除这一行'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
            ),
          ),
        ],
      ),
    );
  }
}

class TimingEditor extends StatelessWidget {
  final String title;
  final String playbackPositionLabel;
  final Duration value;
  final ValueChanged<Duration> onNudge;
  final VoidCallback? onUsePlaybackPosition;

  const TimingEditor({
    required this.title,
    required this.playbackPositionLabel,
    required this.value,
    required this.onNudge,
    this.onUsePlaybackPosition,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                formatLyricDuration(value),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LyricNudgeButton(
                label: '-1s',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(seconds: -1)),
              ),
              LyricNudgeButton(
                label: '-100ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: -100)),
              ),
              LyricNudgeButton(
                label: '-10ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: -10)),
              ),
              LyricNudgeButton(
                label: '+10ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: 10)),
              ),
              LyricNudgeButton(
                label: '+100ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: 100)),
              ),
              LyricNudgeButton(
                label: '+1s',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(seconds: 1)),
              ),
              if (onUsePlaybackPosition != null)
                TextButton.icon(
                  onPressed: onUsePlaybackPosition,
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(playbackPositionLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class AlternativeCandidateCard extends StatelessWidget {
  final String primaryEngine;
  final String alternativeEngine;
  final String? primaryText;
  final String currentText;
  final String alternativeText;
  final VoidCallback? onApply;
  final VoidCallback? onApplyPrimary;
  final bool sharedSecondary;

  const AlternativeCandidateCard({
    required this.primaryEngine,
    required this.alternativeEngine,
    required this.primaryText,
    required this.currentText,
    required this.alternativeText,
    required this.onApply,
    required this.onApplyPrimary,
    this.sharedSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = const CharacterDiffService().diff(
      primaryText ?? currentText,
      alternativeText,
    );
    final minHeight = AppResponsive.of(context).minimumInteractiveExtent;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.info.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            primaryText == null ? '当前歌词' : '$primaryEngine 原始识别',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          _CandidateDiffText(segments: segments, showAlternative: false),
          if (onApplyPrimary != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onApplyPrimary,
                style: TextButton.styleFrom(minimumSize: Size(0, minHeight)),
                child: const Text('采用主模型原文'),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$alternativeEngine 备选',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.info),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CandidateDiffText(segments: segments, showAlternative: true),
          if (sharedSecondary)
            Text(
              '备选片段对应多行歌词，无法直接替换单行；请结合音频手动校对。',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onApply,
                style: TextButton.styleFrom(minimumSize: Size(0, minHeight)),
                child: const Text('采用备选'),
              ),
            ),
          Text(
            '高亮为两份文本的差异；编辑框显示当前歌词。采用只替换文字，不更改时间。',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CandidateDiffText extends StatelessWidget {
  final List<CharacterDiffSegment> segments;
  final bool showAlternative;

  const _CandidateDiffText({
    required this.segments,
    required this.showAlternative,
  });

  @override
  Widget build(BuildContext context) {
    final visible = segments.where(
      (segment) => showAlternative
          ? segment.type != CharacterDiffType.delete
          : segment.type != CharacterDiffType.insert,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final segment in visible)
            TextSpan(
              text: segment.text,
              style: segment.isEqual
                  ? null
                  : TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      backgroundColor: AppColors.info.withAlpha(70),
                    ),
            ),
        ],
      ),
      key: ValueKey(
        showAlternative
            ? 'alternative_candidate_text'
            : 'primary_candidate_text',
      ),
    );
  }
}

class NoSelectionInspector extends StatelessWidget {
  const NoSelectionInspector();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgElevated,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 38,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('选择一行开始校对', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '文本、双引擎备选和时间轴微调都会集中显示在这里。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Explains a row only the secondary engine heard and offers the three
/// decisions: listen, keep it (records a review decision, text unchanged), or
/// reject it (deletes the row through the normal, undoable delete). Nothing is
/// saved automatically; both decisions only change the editor draft.
class SecondarySuggestionCard extends StatelessWidget {
  final SecondaryOnlySuggestion suggestion;
  final VoidCallback onPreview;
  final VoidCallback? onKeep;
  final VoidCallback onReject;

  const SecondarySuggestionCard({
    super.key,
    required this.suggestion,
    required this.onPreview,
    required this.onKeep,
    required this.onReject,
  });

  static String engineLabel(String? engine) {
    final lower = engine?.toLowerCase() ?? '';
    if (lower.contains('whisper')) return 'Whisper';
    if (lower.contains('qwen')) return 'Qwen';
    return '备用引擎';
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = AppResponsive.of(context).minimumInteractiveExtent;
    final theme = Theme.of(context);
    final engine = engineLabel(suggestion.engine);
    return Container(
      key: const ValueKey('secondary_suggestion_card'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.warning.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '建议补入 · 仅 $engine 识别到',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '主引擎在这段时间没有对应歌词。这一行已按时间插入草稿，但尚未确认：'
            '可能是漏识别的歌词，也可能是和声、口白或误识别。请先试听再决定。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                onPressed: onPreview,
                style: TextButton.styleFrom(minimumSize: Size(0, minHeight)),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('试听这一行'),
              ),
              FilledButton.tonal(
                key: const ValueKey('secondary_suggestion_keep'),
                onPressed: onKeep,
                style: FilledButton.styleFrom(minimumSize: Size(0, minHeight)),
                child: const Text('保留并标记已复核'),
              ),
              OutlinedButton(
                key: const ValueKey('secondary_suggestion_reject'),
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: Size(0, minHeight),
                ),
                child: const Text('不补入，删除这一行'),
              ),
            ],
          ),
          Text(
            '两种决定都只修改未保存的草稿，可用撤销恢复。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Split and merge buttons under the lyric text.
///
/// Splitting takes the text cursor as the break; with the cursor at either end
/// (or the field unfocused) it uses the natural break nearest the middle. The
/// boundary time is the paused playhead when it sits inside the row, otherwise
/// it is divided by how much is sung on each side.
class LineStructureActions extends StatelessWidget {
  final VoidCallback? onSplit;
  final VoidCallback? onMergeWithNext;
  final String splitShortcutLabel;

  const LineStructureActions({
    super.key,
    required this.onSplit,
    required this.onMergeWithNext,
    required this.splitShortcutLabel,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final style = OutlinedButton.styleFrom(
      minimumSize: Size(0, spec.minimumInteractiveExtent),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message:
                '从光标处断开为两行（$splitShortcutLabel）；光标不在文字中间时，'
                '从最接近中间的空格或标点断开。暂停在本行内时，以暂停位置作为分界时间',
            child: OutlinedButton.icon(
              key: const ValueKey('inspector_split_line'),
              onPressed: onSplit,
              style: style,
              icon: const Icon(Icons.call_split_rounded, size: 18),
              label: const Text('拆分此行', overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Tooltip(
            message: '把下一行接到这一行后面，时间取两行的起止范围',
            child: OutlinedButton.icon(
              key: const ValueKey('inspector_merge_next'),
              onPressed: onMergeWithNext,
              style: style,
              icon: const Icon(Icons.call_merge_rounded, size: 18),
              label: const Text('与下一行合并', overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ],
    );
  }
}
