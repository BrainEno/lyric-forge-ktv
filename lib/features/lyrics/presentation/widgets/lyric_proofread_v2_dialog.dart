import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/proofreading/proofread_review_proposal.dart';
import '../../domain/proofreading/proofread_strategy_selector.dart';
import '../../domain/proofreading/reference_forced_alignment_planner.dart';
import '../../domain/services/character_diff_service.dart';
import '../lyric_review_strings.dart';

class ProofreadV2RunOptions {
  final LyricSourceStrategy strategy;
  final bool useReference;
  final String? secondaryTranscriptText;
  final bool useForcedAlignment;
  final bool useProjectEvidence;

  const ProofreadV2RunOptions({
    required this.strategy,
    required this.useReference,
    this.secondaryTranscriptText,
    this.useForcedAlignment = false,
    this.useProjectEvidence = false,
  });
}

Future<ProofreadV2RunOptions?> showProofreadV2RunOptionsDialog(
  BuildContext context, {
  bool allowProjectEvidence = false,
}) {
  return showDialog<ProofreadV2RunOptions>(
    context: context,
    builder: (_) => _ProofreadV2RunOptionsDialog(
      allowProjectEvidence: allowProjectEvidence,
    ),
  );
}

class _ProofreadV2RunOptionsDialog extends StatefulWidget {
  final bool allowProjectEvidence;
  const _ProofreadV2RunOptionsDialog({required this.allowProjectEvidence});

  @override
  State<_ProofreadV2RunOptionsDialog> createState() =>
      _ProofreadV2RunOptionsDialogState();
}

class _ProofreadV2RunOptionsDialogState
    extends State<_ProofreadV2RunOptionsDialog> {
  LyricSourceStrategy _strategy = LyricSourceStrategy.auto;
  bool _useReference = false;
  bool _useForcedAlignment = false;
  bool _useProjectEvidence = false;
  final TextEditingController _secondaryTranscriptController =
      TextEditingController();

  @override
  void dispose() {
    _secondaryTranscriptController.dispose();
    super.dispose();
  }

  Widget _revealOnFocus(Widget child) {
    return Builder(
      builder: (context) => Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            unawaited(
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 120),
                alignment: 0.2,
              ),
            );
          });
        },
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      scrollable: true,
      title: const Text('歌词智能校对 V2'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择本次提案策略。生成结果只供复核，不会立即写入工程或磁盘。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _revealOnFocus(
                  ChoiceChip(
                    label: const Text('自动选择'),
                    selected: _strategy == LyricSourceStrategy.auto,
                    onSelected: (_) =>
                        setState(() => _strategy = LyricSourceStrategy.auto),
                  ),
                ),
                _revealOnFocus(
                  ChoiceChip(
                    label: const Text('参考歌词优先'),
                    selected: _strategy == LyricSourceStrategy.referenceFirst,
                    onSelected: (_) => setState(() {
                      _strategy = LyricSourceStrategy.referenceFirst;
                      _useReference = true;
                    }),
                  ),
                ),
                _revealOnFocus(
                  ChoiceChip(
                    label: const Text('ASR 优先'),
                    selected: _strategy == LyricSourceStrategy.asrFirst,
                    onSelected: (_) => setState(() {
                      _strategy = LyricSourceStrategy.asrFirst;
                      _useReference = false;
                    }),
                  ),
                ),
              ],
            ),
            if (_strategy == LyricSourceStrategy.auto) ...[
              const SizedBox(height: 12),
              _revealOnFocus(
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _useReference,
                  onChanged: (value) =>
                      setState(() => _useReference = value ?? false),
                  title: const Text('本次提供参考歌词'),
                  subtitle: const Text('自动策略会先计算文本覆盖率；覆盖率不足时退回 ASR 复核。'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ] else if (_strategy == LyricSourceStrategy.referenceFirst) ...[
              const SizedBox(height: 8),
              const Text('下一步需要粘贴或导入参考歌词。'),
              if (_useProjectEvidence ||
                  _secondaryTranscriptController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('之前配置的 ASR 第二意见在参考歌词优先模式下不会使用；切回其他策略可继续编辑。'),
              ],
            ],
            const SizedBox(height: 8),
            _revealOnFocus(
              CheckboxListTile(
                key: const ValueKey('forced_alignment_review_toggle'),
                contentPadding: EdgeInsets.zero,
                value: _useForcedAlignment,
                onChanged: (value) =>
                    setState(() => _useForcedAlignment = value ?? false),
                title: const Text('使用 ForcedAligner 词级时间证据'),
                subtitle: const Text(
                  '需要本机 Qwen ForcedAligner；ASR 优先对齐草稿，参考优先对齐参考文本。时间仅供复核，不会写入歌词。',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            if (_strategy != LyricSourceStrategy.referenceFirst) ...[
              if (_strategy == LyricSourceStrategy.auto) ...[
                const SizedBox(height: 8),
                const Text(
                  '第二份 ASR 仅在最终选择 ASR 优先时使用；ForcedAligner 使用最终策略的文本。填写的转写稿会先检查格式。',
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '可粘贴第二份带时间戳的转写稿（LRC、SRT 或 WebVTT）。'
                '只有明确的时间戳证据才参与双 ASR 比对；不会自动覆盖原歌词。',
              ),
              const SizedBox(height: 8),
              if (widget.allowProjectEvidence) ...[
                _revealOnFocus(
                  CheckboxListTile(
                    key: const ValueKey('project_asr_evidence_toggle'),
                    contentPadding: EdgeInsets.zero,
                    value: _useProjectEvidence,
                    onChanged: (value) =>
                        setState(() => _useProjectEvidence = value ?? false),
                    title: const Text('使用工程中的独立第二份转写稿'),
                    subtitle: const Text(
                      '仅限与当前草稿一致、音频已校验的完整双引擎快照；选中后暂不使用粘贴稿。校验音频可能需要时间。',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
              _revealOnFocus(
                TextField(
                  enabled: !_useProjectEvidence,
                  key: const ValueKey('secondary_asr_transcript_input'),
                  controller: _secondaryTranscriptController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '第二份 ASR 转写稿（可选）',
                    hintText: '[00:12.30] lyric line…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ProofreadV2RunOptions(
              strategy: _strategy,
              useReference:
                  _strategy == LyricSourceStrategy.referenceFirst ||
                  (_strategy == LyricSourceStrategy.auto && _useReference),
              useProjectEvidence:
                  widget.allowProjectEvidence &&
                  _strategy != LyricSourceStrategy.referenceFirst &&
                  _useProjectEvidence,
              secondaryTranscriptText:
                  !_useProjectEvidence &&
                      _strategy != LyricSourceStrategy.referenceFirst &&
                      _secondaryTranscriptController.text.trim().isNotEmpty
                  ? _secondaryTranscriptController.text.trim()
                  : null,
              useForcedAlignment: _useForcedAlignment,
            ),
          ),
          child: const Text('继续'),
        ),
      ],
    );
  }
}

class ProofreadTimedLinePreviewResult {
  final bool succeeded;
  final String? message;

  const ProofreadTimedLinePreviewResult.success({this.message})
    : succeeded = true;

  const ProofreadTimedLinePreviewResult.failure(String message)
    : succeeded = false,
      message = message;
}

typedef ProofreadTimedLinePreview =
    Future<ProofreadTimedLinePreviewResult> Function(
      int sourceIndex,
      LyricLine line,
      Duration globalOffset,
    );

typedef ReferenceTimingPreview =
    Future<ProofreadTimedLinePreviewResult> Function(
      int proposalIndex,
      int? sourceIndex,
      ReferenceForcedTimingProposal evidence,
    );

Future<LyricProofreadV2Selection?> showLyricProofreadV2ReviewDialog(
  BuildContext context, {
  required String summary,
  required String explanation,
  required List<LyricProofreadV2ReviewItem> items,
  required List<LyricProofreadV2DroppedItem> droppedItems,
  required ValueChanged<int>? onPreviewDraftLine,
  ProofreadTimedLinePreview? onPreviewTimedLine,
  Duration originalGlobalOffset = Duration.zero,
  Duration proposedGlobalOffset = Duration.zero,
  void Function(int sourceIndex, TimedLyricToken token)?
  onPreviewAlignmentToken,
  ProofreadAlignmentDiagnostics? alignmentDiagnostics,
  bool allowReferenceTimingSelection = false,
  ReferenceTimingPreview? onPreviewReferenceTiming,
}) {
  return showDialog<LyricProofreadV2Selection>(
    context: context,
    builder: (_) => _LyricProofreadV2ReviewDialog(
      summary: summary,
      explanation: explanation,
      items: items,
      droppedItems: droppedItems,
      onPreviewDraftLine: onPreviewDraftLine,
      onPreviewTimedLine: onPreviewTimedLine,
      originalGlobalOffset: originalGlobalOffset,
      proposedGlobalOffset: proposedGlobalOffset,
      onPreviewAlignmentToken: onPreviewAlignmentToken,
      alignmentDiagnostics: alignmentDiagnostics,
      allowReferenceTimingSelection: allowReferenceTimingSelection,
      onPreviewReferenceTiming: onPreviewReferenceTiming,
    ),
  );
}

class _LyricProofreadV2ReviewDialog extends StatefulWidget {
  final String summary;
  final String explanation;
  final List<LyricProofreadV2ReviewItem> items;
  final List<LyricProofreadV2DroppedItem> droppedItems;
  final ValueChanged<int>? onPreviewDraftLine;
  final ProofreadTimedLinePreview? onPreviewTimedLine;
  final Duration originalGlobalOffset;
  final Duration proposedGlobalOffset;
  final void Function(int sourceIndex, TimedLyricToken token)?
  onPreviewAlignmentToken;
  final ProofreadAlignmentDiagnostics? alignmentDiagnostics;
  final bool allowReferenceTimingSelection;
  final ReferenceTimingPreview? onPreviewReferenceTiming;

  const _LyricProofreadV2ReviewDialog({
    required this.summary,
    required this.explanation,
    required this.items,
    required this.droppedItems,
    required this.onPreviewDraftLine,
    required this.onPreviewTimedLine,
    required this.originalGlobalOffset,
    required this.proposedGlobalOffset,
    required this.onPreviewAlignmentToken,
    this.alignmentDiagnostics,
    required this.allowReferenceTimingSelection,
    required this.onPreviewReferenceTiming,
  });

  @override
  State<_LyricProofreadV2ReviewDialog> createState() =>
      _LyricProofreadV2ReviewDialogState();
}

class _LyricProofreadV2ReviewDialogState
    extends State<_LyricProofreadV2ReviewDialog> {
  final Set<int> _acceptedAmber = {};
  final Set<int> _restoredDraftIndices = {};
  final Set<int> _acceptedReferenceTimings = {};
  bool _referencePreviewPending = false;
  bool _timedPreviewPending = false;
  bool get _previewPending => _referencePreviewPending || _timedPreviewPending;
  final Map<int, String> _auditionFeedbackByProposal = {};
  final Map<(String, String), List<CharacterDiffSegment>> _textDiffs = {};

  @override
  void didUpdateWidget(covariant _LyricProofreadV2ReviewDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _textDiffs.clear();
  }

  List<LyricProofreadV2ReviewItem> get _greenItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.green)
      .toList(growable: false);

  List<LyricProofreadV2ReviewItem> get _amberItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.amber)
      .toList(growable: false);

  List<LyricProofreadV2ReviewItem> get _lockedItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.locked)
      .toList(growable: false);

  int get _greenChangeCount =>
      _greenItems.where((item) => item.hasChange).length;

  int get _selectedAmberChangeCount => _amberItems
      .where(
        (item) => item.hasChange && _acceptedAmber.contains(item.proposalIndex),
      )
      .length;

  bool get _canApplyGreen => _greenChangeCount > 0;

  bool get _canApplySelected =>
      _greenChangeCount > 0 ||
      _selectedAmberChangeCount > 0 ||
      _restoredDraftIndices.isNotEmpty ||
      _acceptedReferenceTimings.isNotEmpty;

  Future<void> _previewTimedLine({
    required int proposalIndex,
    required int sourceIndex,
    required LyricLine line,
    required Duration globalOffset,
    required String label,
  }) async {
    final preview = widget.onPreviewTimedLine;
    if (preview == null || _previewPending) return;
    setState(() {
      _timedPreviewPending = true;
      _auditionFeedbackByProposal.remove(proposalIndex);
    });
    ProofreadTimedLinePreviewResult result;
    try {
      result = await preview(sourceIndex, line, globalOffset);
    } catch (error) {
      result = ProofreadTimedLinePreviewResult.failure(error.toString());
    }
    if (!mounted) return;
    setState(() {
      _timedPreviewPending = false;
      _auditionFeedbackByProposal[proposalIndex] = result.succeeded
          ? result.message ?? '正在试听$label时间范围；再次点击可暂停。'
          : '试听失败：${result.message ?? '未知原因'}';
    });
  }

  Future<void> _previewReferenceTiming(
    LyricProofreadV2ReviewItem item,
    ReferenceForcedTimingProposal evidence,
  ) async {
    final preview = widget.onPreviewReferenceTiming;
    if (preview == null || _previewPending) return;
    setState(() {
      _referencePreviewPending = true;
      _auditionFeedbackByProposal.remove(item.proposalIndex);
    });
    ProofreadTimedLinePreviewResult result;
    try {
      result = await preview(item.proposalIndex, item.sourceIndex, evidence);
    } catch (error) {
      result = ProofreadTimedLinePreviewResult.failure(error.toString());
    }
    if (!mounted) return;
    setState(() {
      _referencePreviewPending = false;
      _auditionFeedbackByProposal[item.proposalIndex] = result.succeeded
          ? result.message ?? '正在试听参考对齐时间；再次点击可暂停。'
          : '试听失败：${result.message ?? '未知原因'}';
    });
  }

  String _formatTime(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(2)} s';

  String _verdictLabel(LyricProofreadReviewVerdict verdict) {
    return switch (verdict) {
      LyricProofreadReviewVerdict.locked => '受保护',
      LyricProofreadReviewVerdict.green => '绿色 · 可批量应用',
      LyricProofreadReviewVerdict.amber => '琥珀色 · 逐行复核',
    };
  }

  IconData _verdictIcon(LyricProofreadReviewVerdict verdict) {
    return switch (verdict) {
      LyricProofreadReviewVerdict.locked => Icons.lock_outline_rounded,
      LyricProofreadReviewVerdict.green => Icons.check_circle_outline_rounded,
      LyricProofreadReviewVerdict.amber => Icons.warning_amber_rounded,
    };
  }

  void _finish({required bool includeAmber}) {
    final accepted = <int>{
      ..._lockedItems.map((item) => item.proposalIndex),
      ..._greenItems.map((item) => item.proposalIndex),
      if (includeAmber) ..._acceptedAmber,
    };
    Navigator.of(context).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: accepted,
        restoredDraftIndices: _restoredDraftIndices,
        acceptedReferenceTimingIndices: _acceptedReferenceTimings,
      ),
    );
  }

  void _finishGreenOnly() {
    final accepted = <int>{
      ..._lockedItems.map((item) => item.proposalIndex),
      ..._greenItems.map((item) => item.proposalIndex),
    };
    Navigator.of(context).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: accepted,
        restoredDraftIndices: const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      title: const Text('智能校对提案复核'),
      content: SizedBox(
        width: (viewport.width - 80).clamp(200.0, 900.0).toDouble(),
        height: (viewport.height - 230).clamp(240.0, 620.0).toDouble(),
        child: ListView(
          children: [
            Text(widget.summary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              widget.explanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.alignmentDiagnostics != null)
              _buildAlignmentDiagnostics(widget.alignmentDiagnostics!),
            const SizedBox(height: 8),
            Text(
              '绿色行可批量应用；琥珀色行默认不采纳，需逐项勾选；'
              '灰色行默认排除，勾选后会恢复原文。原文与建议中加粗、下划线标出文字差异。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            for (final item in widget.items) _buildProposalCard(item),
            if (widget.droppedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '灰色行 · 疑似多余（${widget.droppedItems.length}）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final item in widget.droppedItems)
                CheckboxListTile(
                  key: ValueKey('restore_dropped_${item.sourceIndex}'),
                  value: _restoredDraftIndices.contains(item.sourceIndex),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _restoredDraftIndices.add(item.sourceIndex);
                    } else {
                      _restoredDraftIndices.remove(item.sourceIndex);
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary:
                      widget.onPreviewTimedLine == null &&
                          widget.onPreviewDraftLine == null
                      ? null
                      : IconButton(
                          key: ValueKey('preview_dropped_${item.sourceIndex}'),
                          tooltip: '试听原始行',
                          onPressed: _previewPending
                              ? null
                              : widget.onPreviewTimedLine == null
                              ? () =>
                                    widget.onPreviewDraftLine!(item.sourceIndex)
                              : () => _previewTimedLine(
                                  proposalIndex: -item.sourceIndex - 1,
                                  sourceIndex: item.sourceIndex,
                                  line: item.line,
                                  globalOffset: widget.originalGlobalOffset,
                                  label: '原始',
                                ),
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                  title: Text(
                    '第 ${item.sourceIndex + 1} 行 · ${item.line.text}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatTime(item.line.startTime)} – '
                        '${_formatTime(item.line.endTime)} · '
                        '${LyricReviewStrings.droppedReferenceItemReason}',
                      ),
                      if (_auditionFeedbackByProposal[-item.sourceIndex - 1] !=
                          null)
                        Text(
                          _auditionFeedbackByProposal[-item.sourceIndex - 1]!,
                          key: ValueKey(
                            'audition_feedback_dropped_${item.sourceIndex}',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _canApplyGreen ? _finishGreenOnly : null,
          child: Text('仅应用绿色（$_greenChangeCount）'),
        ),
        FilledButton.icon(
          onPressed: _canApplySelected
              ? () => _finish(includeAmber: true)
              : null,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            _acceptedReferenceTimings.isEmpty
                ? '应用所选（绿色 + 琥珀色 $_selectedAmberChangeCount）'
                : '应用所选（琥珀色 $_selectedAmberChangeCount · 对齐时间 ${_acceptedReferenceTimings.length}）',
          ),
        ),
      ],
    );
  }

  Widget _buildAlignmentDiagnostics(ProofreadAlignmentDiagnostics diagnostics) {
    final coverageLabel = diagnostics.totalLineCount == 0
        ? '无歌词行'
        : '${(diagnostics.lineCoverage * 100).round()}%';
    return Container(
      key: const ValueKey('forced_alignment_diagnostics'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border.all(
          color: diagnostics.isComplete
              ? AppColors.textTertiary
              : Colors.amber.shade400,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ForcedAligner 覆盖：${diagnostics.matchedLineCount}/'
            '${diagnostics.totalLineCount} 行（$coverageLabel）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (diagnostics.hasSkippedSpans)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '未分配对齐片段：${diagnostics.skippedSpanCount}（需要人工判定）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (diagnostics.hasUnmatchedLines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '未匹配歌词行：${diagnostics.unmatchedLineNumbers.join('、')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '词级时间仅供人工复核；不自动修改歌词行级时间戳。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDiffText(
    int proposalIndex,
    List<CharacterDiffSegment> segments, {
    required bool proposed,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: proposed ? '建议：' : '原文：'),
          for (final segment in segments)
            if (segment.type !=
                (proposed
                    ? CharacterDiffType.delete
                    : CharacterDiffType.insert))
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
        'proofread_${proposed ? 'proposed' : 'original'}_diff_$proposalIndex',
      ),
      style: proposed ? const TextStyle(fontWeight: FontWeight.w600) : null,
    );
  }

  bool _canSelectReferenceTiming(LyricProofreadV2ReviewItem item) {
    final evidence = item.referenceTimingEvidence;
    if (!widget.allowReferenceTimingSelection ||
        evidence == null ||
        item.verdict == LyricProofreadReviewVerdict.locked)
      return false;
    final accepted =
        item.verdict == LyricProofreadReviewVerdict.green ||
        _acceptedAmber.contains(item.proposalIndex);
    if (item.sourceIndex == null && !accepted) return false;
    final text = accepted ? item.proposedLine.text : item.originalLine?.text;
    return text == evidence.referenceText &&
        evidence.start >= widget.originalGlobalOffset;
  }

  Widget _buildProposalCard(LyricProofreadV2ReviewItem item) {
    final original = item.originalLine;
    final segments = original != null && original.text != item.proposedLine.text
        ? _textDiffs.putIfAbsent(
            (original.text, item.proposedLine.text),
            () => const CharacterDiffService().diff(
              original.text,
              item.proposedLine.text,
            ),
          )
        : null;
    final reasonText = [
      ...item.referenceReasons.map(LyricReviewStrings.referenceReason),
      ...item.proofreadReasons.map(LyricReviewStrings.proofreadReason),
      ...item.alignmentHints.map(
        (hint) => LyricReviewStrings.alignmentHint(
          hint,
          wordCount: item.alignmentTokens.length,
        ),
      ),
    ].join('、');
    final verdictColor = switch (item.verdict) {
      LyricProofreadReviewVerdict.locked => AppColors.textTertiary,
      LyricProofreadReviewVerdict.green => Colors.green.shade400,
      LyricProofreadReviewVerdict.amber => Colors.amber.shade300,
    };
    return Card(
      key: ValueKey('proofread_proposal_${item.proposalIndex}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.bgBase,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_verdictIcon(item.verdict), color: verdictColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.sourceIndex == null ? '参考新增行' : '第 ${item.sourceIndex! + 1} 行'}'
                    ' · ${_verdictLabel(item.verdict)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (item.sourceIndex != null &&
                    original != null &&
                    (widget.onPreviewTimedLine != null ||
                        widget.onPreviewDraftLine != null))
                  IconButton(
                    key: ValueKey('preview_original_${item.proposalIndex}'),
                    tooltip: '试听原始行',
                    visualDensity: VisualDensity.compact,
                    onPressed: _previewPending
                        ? null
                        : widget.onPreviewTimedLine == null
                        ? () => widget.onPreviewDraftLine!(item.sourceIndex!)
                        : () => _previewTimedLine(
                            proposalIndex: item.proposalIndex,
                            sourceIndex: item.sourceIndex!,
                            line: original,
                            globalOffset: widget.originalGlobalOffset,
                            label: '原始',
                          ),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                  ),
                if (item.sourceIndex != null &&
                    widget.onPreviewTimedLine != null)
                  IconButton(
                    key: ValueKey('preview_proposed_${item.proposalIndex}'),
                    tooltip: '试听建议时间',
                    visualDensity: VisualDensity.compact,
                    onPressed: _previewPending
                        ? null
                        : () => _previewTimedLine(
                            proposalIndex: item.proposalIndex,
                            sourceIndex: item.sourceIndex!,
                            line: item.proposedLine,
                            globalOffset: widget.proposedGlobalOffset,
                            label: '建议',
                          ),
                    icon: const Icon(Icons.hearing_rounded),
                  ),
              ],
            ),
            if (original == null)
              const Text('原文：无（这是待插入的参考行）')
            else ...[
              if (segments == null)
                Text('原文：${original.text}')
              else
                _buildDiffText(item.proposalIndex, segments, proposed: false),
              Text(
                '时间：${_formatTime(original.startTime)} – '
                '${_formatTime(original.endTime)}',
              ),
            ],
            if (segments == null)
              Text(
                '建议：${item.proposedLine.text}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            else
              _buildDiffText(item.proposalIndex, segments, proposed: true),
            Text(
              '建议时间：${_formatTime(item.proposedLine.startTime)} – '
              '${_formatTime(item.proposedLine.endTime)}',
            ),
            if (item.referenceTimingEvidence case final evidence?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '参考文本对齐证据 · ${evidence.source}',
                      key: ValueKey(
                        'reference_alignment_source_${item.proposalIndex}',
                      ),
                    ),
                    Text('对齐文本：${evidence.referenceText}'),
                    Text(
                      '对齐时间（绝对音频时间）：${_formatTime(evidence.start)} – ${_formatTime(evidence.end)}',
                    ),
                    const Text('时间来自参考文本对齐，可能不准确；须逐行勾选才会采纳。'),
                    TextButton.icon(
                      key: ValueKey(
                        'preview_reference_timing_${item.proposalIndex}',
                      ),
                      onPressed:
                          widget.onPreviewReferenceTiming == null ||
                              _previewPending
                          ? null
                          : () => _previewReferenceTiming(item, evidence),
                      icon: const Icon(Icons.headphones_rounded),
                      label: Text(
                        _referencePreviewPending ? '正在检查音源…' : '试听参考对齐时间',
                      ),
                    ),
                    if (widget.onPreviewReferenceTiming == null)
                      const Text('音源未通过校验，暂不能试听参考对齐时间。'),
                    CheckboxListTile(
                      key: ValueKey(
                        'accept_reference_timing_${item.proposalIndex}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      value: _acceptedReferenceTimings.contains(
                        item.proposalIndex,
                      ),
                      onChanged: _canSelectReferenceTiming(item)
                          ? (checked) => setState(() {
                              if (checked == true) {
                                _acceptedReferenceTimings.add(
                                  item.proposalIndex,
                                );
                              } else {
                                _acceptedReferenceTimings.remove(
                                  item.proposalIndex,
                                );
                              }
                            })
                          : null,
                      title: const Text('采纳此行参考对齐时间'),
                      subtitle: Text(
                        !widget.allowReferenceTimingSelection
                            ? '音源尚未通过校验，暂不可采纳。'
                            : item.verdict == LyricProofreadReviewVerdict.locked
                            ? '受保护行不可更改时间。'
                            : !_canSelectReferenceTiming(item)
                            ? '需先采纳匹配的参考文字或新增行，并确保偏移后时间非负。'
                            : '仅在应用所选时写入；绿色批量应用不会采纳此时间。',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            if (reasonText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '依据：$reasonText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_auditionFeedbackByProposal[item.proposalIndex] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _auditionFeedbackByProposal[item.proposalIndex]!,
                  key: ValueKey('audition_feedback_${item.proposalIndex}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (item.alignmentTokens.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ExpansionTile(
                  key: ValueKey('alignment_tokens_${item.proposalIndex}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
                  title: Text('词级时间证据（${item.alignmentTokens.length} 词）'),
                  subtitle: const Text('可逐词试听；对齐时间仅供复核，不会自动应用。'),
                  children: [
                    for (
                      var tokenIndex = 0;
                      tokenIndex < item.alignmentTokens.length;
                      tokenIndex++
                    )
                      () {
                        final token = item.alignmentTokens[tokenIndex];
                        final confidenceLabel = token.confidence == null
                            ? '置信度未提供'
                            : '置信度 ${token.confidence}%';
                        final canPreview =
                            item.sourceIndex != null &&
                            !_previewPending &&
                            widget.onPreviewAlignmentToken != null;
                        return ListTile(
                          key: ValueKey(
                            'alignment_token_row_${item.proposalIndex}_$tokenIndex',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(token.text),
                          subtitle: Text(
                            '${_formatTime(token.interval.start)} – '
                            '${_formatTime(token.interval.end)} · $confidenceLabel',
                          ),
                          trailing: IconButton(
                            key: ValueKey(
                              'alignment_token_${item.proposalIndex}_$tokenIndex',
                            ),
                            tooltip: '试听词语：${token.text}',
                            onPressed: canPreview
                                ? () => widget.onPreviewAlignmentToken!(
                                    item.sourceIndex!,
                                    token,
                                  )
                                : null,
                            icon: const Icon(Icons.play_circle_outline_rounded),
                          ),
                        );
                      }(),
                  ],
                ),
              ),
            if (item.verdict == LyricProofreadReviewVerdict.amber)
              CheckboxListTile(
                key: ValueKey('accept_amber_${item.proposalIndex}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _acceptedAmber.contains(item.proposalIndex),
                onChanged: item.hasChange
                    ? (checked) => setState(() {
                        if (checked == true) {
                          _acceptedAmber.add(item.proposalIndex);
                        } else {
                          _acceptedAmber.remove(item.proposalIndex);
                        }
                        if (!_canSelectReferenceTiming(item)) {
                          _acceptedReferenceTimings.remove(item.proposalIndex);
                        }
                      })
                    : null,
                title: Text(item.hasChange ? '采纳这条琥珀色建议' : '没有可应用的行级变化'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
    );
  }
}
