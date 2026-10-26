import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/proofread_strategy_selector.dart';

class ProofreadV2RunOptions {
  final LyricSourceStrategy strategy;
  final bool useReference;
  final String? secondaryTranscriptText;
  final bool useForcedAlignment;

  const ProofreadV2RunOptions({
    required this.strategy,
    required this.useReference,
    this.secondaryTranscriptText,
    this.useForcedAlignment = false,
  });
}

Future<ProofreadV2RunOptions?> showProofreadV2RunOptionsDialog(
  BuildContext context,
) {
  return showDialog<ProofreadV2RunOptions>(
    context: context,
    builder: (_) => const _ProofreadV2RunOptionsDialog(),
  );
}

class _ProofreadV2RunOptionsDialog extends StatefulWidget {
  const _ProofreadV2RunOptionsDialog();

  @override
  State<_ProofreadV2RunOptionsDialog> createState() =>
      _ProofreadV2RunOptionsDialogState();
}

class _ProofreadV2RunOptionsDialogState
    extends State<_ProofreadV2RunOptionsDialog> {
  LyricSourceStrategy _strategy = LyricSourceStrategy.auto;
  bool _useReference = false;
  bool _useForcedAlignment = false;
  final TextEditingController _secondaryTranscriptController = TextEditingController();

  @override
  void dispose() {
    _secondaryTranscriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
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
                ChoiceChip(
                  label: const Text('自动选择'),
                  selected: _strategy == LyricSourceStrategy.auto,
                  onSelected: (_) => setState(
                    () => _strategy = LyricSourceStrategy.auto,
                  ),
                ),
                ChoiceChip(
                  label: const Text('参考歌词优先'),
                  selected: _strategy == LyricSourceStrategy.referenceFirst,
                  onSelected: (_) => setState(() {
                    _strategy = LyricSourceStrategy.referenceFirst;
                    _useReference = true;
                  }),
                ),
                ChoiceChip(
                  label: const Text('ASR 优先'),
                  selected: _strategy == LyricSourceStrategy.asrFirst,
                  onSelected: (_) => setState(() {
                    _strategy = LyricSourceStrategy.asrFirst;
                    _useReference = false;
                  }),
                ),
              ],
            ),
            if (_strategy == LyricSourceStrategy.auto) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _useReference,
                onChanged: (value) =>
                    setState(() => _useReference = value ?? false),
                title: const Text('本次提供参考歌词'),
                subtitle: const Text(
                  '自动策略会先计算文本覆盖率；覆盖率不足时退回 ASR 复核。',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ] else if (_strategy == LyricSourceStrategy.referenceFirst) ...[
              const SizedBox(height: 8),
              const Text('下一步需要粘贴或导入参考歌词。'),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                '可粘贴第二份带时间戳的转写稿（LRC、SRT 或 WebVTT）。'
                '只有明确的时间戳证据才参与双 ASR 比对；不会自动覆盖原歌词。',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('forced_alignment_review_toggle'),
                contentPadding: EdgeInsets.zero,
                value: _useForcedAlignment,
                onChanged: (value) => setState(
                  () => _useForcedAlignment = value ?? false,
                ),
                title: const Text('使用 ForcedAligner 词级时间证据'),
                subtitle: const Text(
                  '需要本机 Qwen ForcedAligner 运行时；结果只用于复核，不自动修改歌词时间。',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              TextField(
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
              useReference: _strategy == LyricSourceStrategy.referenceFirst ||
                  (_strategy == LyricSourceStrategy.auto && _useReference),
              secondaryTranscriptText: _strategy == LyricSourceStrategy.asrFirst &&
                      _secondaryTranscriptController.text.trim().isNotEmpty
                  ? _secondaryTranscriptController.text.trim()
                  : null,
              useForcedAlignment: _strategy == LyricSourceStrategy.asrFirst &&
                  _useForcedAlignment,
            ),
          ),
          child: const Text('继续'),
        ),
      ],
    );
  }
}

enum LyricProofreadReviewVerdict { locked, green, amber }

class LyricProofreadV2ReviewItem {
  final int proposalIndex;
  final int? sourceIndex;
  final LyricLine proposedLine;
  final LyricLine? originalLine;
  final LyricProofreadReviewVerdict verdict;
  final String reasonLabel;

  const LyricProofreadV2ReviewItem({
    required this.proposalIndex,
    required this.sourceIndex,
    required this.proposedLine,
    required this.originalLine,
    required this.verdict,
    required this.reasonLabel,
  });

  bool get hasChange {
    final original = originalLine;
    if (original == null) return true;
    return original.text != proposedLine.text ||
        original.startTime != proposedLine.startTime ||
        original.endTime != proposedLine.endTime ||
        original.isChorus != proposedLine.isChorus ||
        original.confidence != proposedLine.confidence;
  }
}

class LyricProofreadV2DroppedItem {
  final int sourceIndex;
  final LyricLine line;
  final String reasonLabel;

  const LyricProofreadV2DroppedItem({
    required this.sourceIndex,
    required this.line,
    required this.reasonLabel,
  });
}

class LyricProofreadV2Selection {
  final Set<int> acceptedProposalIndices;
  final Set<int> restoredDraftIndices;

  LyricProofreadV2Selection({
    required Set<int> acceptedProposalIndices,
    required Set<int> restoredDraftIndices,
  }) : acceptedProposalIndices = Set.unmodifiable(acceptedProposalIndices),
       restoredDraftIndices = Set.unmodifiable(restoredDraftIndices);
}

Future<LyricProofreadV2Selection?> showLyricProofreadV2ReviewDialog(
  BuildContext context, {
  required String summary,
  required String explanation,
  required List<LyricProofreadV2ReviewItem> items,
  required List<LyricProofreadV2DroppedItem> droppedItems,
  required ValueChanged<int>? onPreviewDraftLine,
}) {
  return showDialog<LyricProofreadV2Selection>(
    context: context,
    builder: (_) => _LyricProofreadV2ReviewDialog(
      summary: summary,
      explanation: explanation,
      items: items,
      droppedItems: droppedItems,
      onPreviewDraftLine: onPreviewDraftLine,
    ),
  );
}

class _LyricProofreadV2ReviewDialog extends StatefulWidget {
  final String summary;
  final String explanation;
  final List<LyricProofreadV2ReviewItem> items;
  final List<LyricProofreadV2DroppedItem> droppedItems;
  final ValueChanged<int>? onPreviewDraftLine;

  const _LyricProofreadV2ReviewDialog({
    required this.summary,
    required this.explanation,
    required this.items,
    required this.droppedItems,
    required this.onPreviewDraftLine,
  });

  @override
  State<_LyricProofreadV2ReviewDialog> createState() =>
      _LyricProofreadV2ReviewDialogState();
}

class _LyricProofreadV2ReviewDialogState
    extends State<_LyricProofreadV2ReviewDialog> {
  final Set<int> _acceptedAmber = {};
  final Set<int> _restoredDraftIndices = {};

  List<LyricProofreadV2ReviewItem> get _greenItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.green)
      .toList(growable: false);

  List<LyricProofreadV2ReviewItem> get _amberItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.amber)
      .toList(growable: false);

  List<LyricProofreadV2ReviewItem> get _lockedItems => widget.items
      .where((item) => item.verdict == LyricProofreadReviewVerdict.locked)
      .toList(growable: false);

  int get _greenChangeCount => _greenItems.where((item) => item.hasChange).length;

  int get _selectedAmberChangeCount => _amberItems
      .where(
        (item) => item.hasChange && _acceptedAmber.contains(item.proposalIndex),
      )
      .length;

  bool get _canApplyGreen => _greenChangeCount > 0;

  bool get _canApplySelected =>
      _greenChangeCount > 0 ||
      _selectedAmberChangeCount > 0 ||
      _restoredDraftIndices.isNotEmpty;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.summary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              widget.explanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '绿色行可批量应用；琥珀色行默认不采纳，需逐项勾选；'
              '灰色行默认排除，勾选后会恢复原文。每行均保留原文与建议的逐行对比。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                children: [
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
                        secondary: widget.onPreviewDraftLine == null
                            ? null
                            : IconButton(
                                tooltip: '试听原始行',
                                onPressed: () => widget.onPreviewDraftLine!(
                                  item.sourceIndex,
                                ),
                                icon: const Icon(Icons.play_circle_outline),
                              ),
                        title: Text('第 ${item.sourceIndex + 1} 行 · ${item.line.text}'),
                        subtitle: Text(
                          '${_formatTime(item.line.startTime)} – '
                          '${_formatTime(item.line.endTime)} · '
                          '${item.reasonLabel} · 默认排除，勾选恢复',
                        ),
                      ),
                  ],
                ],
              ),
            ),
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
          onPressed: _canApplySelected ? () => _finish(includeAmber: true) : null,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            '应用所选（绿色 + 琥珀色 $_selectedAmberChangeCount）',
          ),
        ),
      ],
    );
  }

  Widget _buildProposalCard(LyricProofreadV2ReviewItem item) {
    final original = item.originalLine;
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
                Icon(
                  _verdictIcon(item.verdict),
                  color: verdictColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item.sourceIndex == null ? '参考新增行' : '第 ${item.sourceIndex! + 1} 行'}'
                    ' · ${_verdictLabel(item.verdict)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (item.sourceIndex != null &&
                    widget.onPreviewDraftLine != null)
                  IconButton(
                    tooltip: '试听原始行',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        widget.onPreviewDraftLine!(item.sourceIndex!),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                  ),
              ],
            ),
            if (original == null)
              const Text('原文：无（这是待插入的参考行）')
            else ...[
              Text('原文：${original.text}'),
              Text(
                '时间：${_formatTime(original.startTime)} – '
                '${_formatTime(original.endTime)}',
              ),
            ],
            Text(
              '建议：${item.proposedLine.text}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '建议时间：${_formatTime(item.proposedLine.startTime)} – '
              '${_formatTime(item.proposedLine.endTime)}',
            ),
            if (item.reasonLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '依据：${item.reasonLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
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
                      })
                    : null,
                title: Text(
                  item.hasChange ? '采纳这条琥珀色建议' : '没有可应用的行级变化',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
    );
  }
}
