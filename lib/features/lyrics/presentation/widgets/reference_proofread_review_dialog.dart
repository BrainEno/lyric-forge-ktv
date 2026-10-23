import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/asr_reference_correction_suggester.dart';

/// Explicit line-by-line review for reference-text suggestions.
/// This dialog never treats reference timestamps as timing evidence.
Future<Set<int>?> showReferenceProofreadReviewDialog(
  BuildContext context, {
  required LyricDocument document,
  required List<AsrReferenceCorrectionSuggestion> suggestions,
}) {
  return showDialog<Set<int>>(
    context: context,
    builder: (context) => _ReferenceProofreadReviewDialog(
      document: document,
      suggestions: suggestions,
    ),
  );
}

class _ReferenceProofreadReviewDialog extends StatefulWidget {
  final LyricDocument document;
  final List<AsrReferenceCorrectionSuggestion> suggestions;

  const _ReferenceProofreadReviewDialog({
    required this.document,
    required this.suggestions,
  });

  @override
  State<_ReferenceProofreadReviewDialog> createState() =>
      _ReferenceProofreadReviewDialogState();
}

class _ReferenceProofreadReviewDialogState
    extends State<_ReferenceProofreadReviewDialog> {
  late final Set<int> _selected = {
    for (final item in widget.suggestions)
      if (!item.requiresManualReview) item.draftIndex,
  };

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width - 48).clamp(0, 720).toDouble();
    final dialogHeight = (viewport.height - 240).clamp(180, 460).toDouble();
    final eligibleCount = widget.suggestions
        .where((item) => !item.requiresManualReview)
        .length;
    return AlertDialog(
      title: const Text('参考歌词智能纠错'),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '找到 ${widget.suggestions.length} 条候选。只替换明确匹配的歌词文字，'
              '保留现有时间戳；参考歌词时间不会被当作校准依据。'
              '低置信度、结构不匹配或参考文件有警告的行需人工处理。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('可安全应用：$eligibleCount 行'),
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
                                  widget.suggestions
                                      .where((item) =>
                                          !item.requiresManualReview)
                                      .map((item) => item.draftIndex),
                                );
                            }
                          }),
                  child: Text(_selected.length == eligibleCount ? '取消全选' : '全选安全项'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: widget.suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.suggestions[index];
                  final eligible = !item.requiresManualReview &&
                      item.draftIndex >= 0 &&
                      item.draftIndex < widget.document.lines.length &&
                      widget.document.lines[item.draftIndex].text ==
                          item.currentText;
                  final stale = item.draftIndex < 0 ||
                      item.draftIndex >= widget.document.lines.length ||
                      widget.document.lines[item.draftIndex].text !=
                          item.currentText;
                  final enabled = eligible && !stale;
                  return CheckboxListTile(
                    value: enabled && _selected.contains(item.draftIndex),
                    onChanged: enabled
                        ? (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(item.draftIndex);
                              } else {
                                _selected.remove(item.draftIndex);
                              }
                            })
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('第 ${item.draftIndex + 1} 行 · '
                        '${(item.similarity * 100).round()}% 匹配'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('原文：${item.currentText}'),
                        Text(
                          '建议：${item.suggestedText}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (stale)
                          const Text('草稿已变化，请重新生成建议。')
                        else if (!eligible)
                          const Text('需人工复核；此项不能批量应用。')
                        else
                          const Text('应用后保留当前起止时间。'),
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
              : () => Navigator.of(context).pop(Set<int>.unmodifiable(_selected)),
          icon: const Icon(Icons.check),
          label: Text('应用所选（${_selected.length}）'),
        ),
      ],
    );
  }
}
