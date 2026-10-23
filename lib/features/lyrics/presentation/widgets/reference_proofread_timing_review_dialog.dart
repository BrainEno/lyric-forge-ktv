import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/reference_proofread_review_builder.dart';

Future<Set<int>?> showReferenceProofreadTimingReviewDialog(
  BuildContext context, {
  required LyricDocument document,
  required List<ReferenceProofreadReviewItem> items,
}) {
  return showDialog<Set<int>>(
    context: context,
    builder: (_) => _ReferenceProofreadTimingReviewDialog(
      document: document,
      items: items,
    ),
  );
}

class _ReferenceProofreadTimingReviewDialog extends StatefulWidget {
  final LyricDocument document;
  final List<ReferenceProofreadReviewItem> items;

  const _ReferenceProofreadTimingReviewDialog({
    required this.document,
    required this.items,
  });

  @override
  State<_ReferenceProofreadTimingReviewDialog> createState() =>
      _ReferenceProofreadTimingReviewDialogState();
}

class _ReferenceProofreadTimingReviewDialogState
    extends State<_ReferenceProofreadTimingReviewDialog> {
  late final Set<int> _selected = {
    for (final item in widget.items)
      if (_eligible(item)) item.correction.draftIndex,
  };

  bool _eligible(ReferenceProofreadReviewItem item) {
    final index = item.correction.draftIndex;
    return item.canOfferCompleteProposal &&
        index >= 0 &&
        index < widget.document.lines.length &&
        widget.document.lines[index].text == item.correction.currentText &&
        item.retiming.options.length == 1;
  }

  String _reasonLabel(Object reason) {
    final name = reason.toString().split('.').last;
    return switch (name) {
      'exactTimedTextMatch' => '精确文本匹配',
      'splitAcrossEvidenceLines' => '证据跨多行',
      'textUnchanged' => '文本未变化',
      'emptyProposedText' => '建议文本为空',
      'protectedLine' => '该行受手动编辑保护',
      'noExactNearbyMatch' => '附近没有精确时间证据',
      'multipleMatchingWindows' => '存在多个匹配位置',
      'lowConfidence' => '证据置信度不足',
      'overlapsPreviousLine' => '与上一行时间冲突',
      'overlapsNextLine' => '与下一行时间冲突',
      'negativeStart' => '起始时间为负数',
      'nonPositiveDuration' => '时间区间无效',
      'durationTooShort' => '时间区间过短',
      'beyondAudioDuration' => '超出音频时长',
      'invalidOriginalTiming' => '原始时间区间无效',
      _ => name,
    };
  }

  String _formatTime(Duration value) {
    final seconds = value.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(2)} s';
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final eligibleCount = widget.items.where(_eligible).length;
    return AlertDialog(
      title: const Text('参考歌词纠错与校时复核'),
      content: SizedBox(
        width: (viewport.width - 48).clamp(0, 760).toDouble(),
        height: (viewport.height - 240).clamp(180, 500).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '校时建议只来自独立 ASR JSON 中的时间戳和置信度。'
              '只有唯一匹配、置信度达标且不引入边界冲突的行可批量应用；'
              '其余行保留为人工复核。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('可应用完整建议：$eligibleCount 行'),
                const Spacer(),
                TextButton(
                  onPressed: eligibleCount == 0
                      ? null
                      : () => setState(() {
                          if (_selected.length == eligibleCount) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(
                                widget.items
                                    .where(_eligible)
                                    .map(
                                      (item) => item.correction.draftIndex,
                                    ),
                              );
                          }
                        }),
                  child: Text(
                    _selected.length == eligibleCount ? '取消全选' : '全选安全项',
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final correction = item.correction;
                  final timing = item.retiming;
                  final eligible = _eligible(item);
                  final option = timing.options.length == 1
                      ? timing.options.single
                      : null;
                  final reason = timing.reasons.map(_reasonLabel).join('、');
                  return CheckboxListTile(
                    value:
                        eligible && _selected.contains(correction.draftIndex),
                    onChanged: eligible
                        ? (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(correction.draftIndex);
                            } else {
                              _selected.remove(correction.draftIndex);
                            }
                          })
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      '第 ${correction.draftIndex + 1} 行 · '
                      '${(correction.similarity * 100).round()}% 文本匹配',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('原文：${correction.currentText}'),
                        Text(
                          '建议：${correction.suggestedText}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (option != null)
                          Text(
                            '时间：${_formatTime(option.startTime)} – '
                            '${_formatTime(option.endTime)} · '
                            '证据置信度 ${option.meanConfidence}%',
                          ),
                        Text(
                          eligible
                              ? '可应用文字与时间（应用前仍需确认）'
                              : '暂不可批量应用：$reason',
                        ),
                      ],
                    ),
                  );
                },
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
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  Set<int>.unmodifiable(_selected),
                ),
          icon: const Icon(Icons.check),
          label: Text('应用所选（${_selected.length}）'),
        ),
      ],
    );
  }
}
