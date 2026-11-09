import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/services/character_diff_service.dart';
import 'lyric_editor_atoms.dart';

/// Right-hand inspector for the selected line: timestamps, confidence, nudges
/// and alternative candidates.
///
/// Extracted from the editor screen (Phase 4.1); its parameters are unchanged.

class InspectorPane extends StatelessWidget {
  final LyricDocument document;
  final int? selectedIndex;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int? currentPlaybackLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<int> onPreviewLine;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;
  final bool autofocusText;
  final int focusRequestId;

  const InspectorPane({
    required this.document,
    required this.selectedIndex,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.currentPlaybackLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onPreviewLine,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
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
      isReviewed: isReviewed,
      onReviewDecision: onReviewDecision,
      isCurrentPlaybackLine:
          playbackBelongsToProject && currentPlaybackLine == index,
      isPlaying: playbackBelongsToProject && playback.isPlaying,
      autofocusText: autofocusText,
      onUpdate: (updated) => onUpdateLine(index, updated),
      onDelete: () => onDeleteLine(index),
      onPreview: () => onPreviewLine(index),
      onUsePlaybackAsStart: playbackBelongsToProject
          ? () => onSetStartFromPlayback(index)
          : null,
      onUsePlaybackAsEnd: playbackBelongsToProject
          ? () => onSetEndFromPlayback(index)
          : null,
    );
  }
}

class LineInspector extends StatefulWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final bool isCurrentPlaybackLine;
  final bool isPlaying;
  final bool autofocusText;
  final ValueChanged<LyricLine> onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback? onUsePlaybackAsStart;
  final VoidCallback? onUsePlaybackAsEnd;

  const LineInspector({
    super.key,
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.isCurrentPlaybackLine,
    required this.isPlaying,
    this.autofocusText = false,
    required this.onUpdate,
    required this.onDelete,
    required this.onPreview,
    this.onUsePlaybackAsStart,
    this.onUsePlaybackAsEnd,
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
      null when candidate['qwenText'] != null => candidate['whisperText'],
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
      null when candidate['qwenText'] != null => 'qwenText',
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
            ],
          ),
          if (widget.onReviewDecision != null &&
              widget.line.id?.isNotEmpty == true) ...[
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
          TextField(
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
              alternativeEngine: _engineLabel(
                widget.fallbackCandidate!['alternativeEngine']?.toString() ??
                    (widget.fallbackCandidate!['whisperText'] != null
                        ? 'whisper'
                        : null),
              ),
              primaryText: _primaryText(),
              currentText: _workingLine.text,
              alternativeText: alternative!,
              onApply: () => _applyCandidate(alternative!),
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
  final VoidCallback onApply;
  final VoidCallback? onApplyPrimary;

  const AlternativeCandidateCard({
    required this.primaryEngine,
    required this.alternativeEngine,
    required this.primaryText,
    required this.currentText,
    required this.alternativeText,
    required this.onApply,
    required this.onApplyPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final segments = const CharacterDiffService().diff(
      primaryText ?? currentText,
      alternativeText,
    );
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
                child: const Text('采用主模型原文'),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$alternativeEngine 备选',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.info,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CandidateDiffText(segments: segments, showAlternative: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onApply, child: const Text('采用备选')),
          ),
          Text(
            '高亮为两份文本的差异；编辑框显示当前歌词。采用只替换文字，不更改时间。',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
            ),
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
      key: ValueKey(showAlternative ? 'alternative_candidate_text' : 'primary_candidate_text'),
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
