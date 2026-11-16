import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_structure_advisor.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the line-structure tool.
class LyricStructureStrings {
  const LyricStructureStrings._();

  static const String actionTitle = '整理断行';
  static const String actionDetail = '不需要参考歌词；拆分过长的行、合并被停顿切碎的短行';
  static const String intro =
      '识别器按停顿切分，常把两句歌词并成一行，或把一句切出一个碎片。'
      '这里只列出建议：过长的行从最接近中间的空格或标点处拆开，分界时间按字数比例估算；'
      '间隔很短的碎片行并入相邻行。手动编辑过的行和“建议补入”行不会改动。'
      '结果可撤销，保存后才写盘。';

  static String applied(int splits, int merges) {
    final parts = [
      if (splits > 0) '拆分 $splits 行',
      if (merges > 0) '合并 $merges 处',
    ];
    return '已${parts.join('、')}（未写入磁盘），分界时间可在检查器里微调';
  }

  static String note(LyricStructureSuggestion suggestion) {
    switch (suggestion.kind) {
      case LyricStructureSuggestionKind.splitLongLine:
        final time = suggestion.splitTime;
        final at = time == null ? '' : '，分界约 ${_seconds(time)}';
        return suggestion.confident
            ? '过长，建议拆分$at'
            : '过长且没有空格或标点，按中间拆分$at，请先试听确认';
      case LyricStructureSuggestionKind.mergeFragment:
        return '与第 ${suggestion.index + 2} 行间隔很短，建议合并';
    }
  }

  static String _seconds(Duration value) {
    final totalCentis = value.inMilliseconds ~/ 10;
    final minutes = totalCentis ~/ 6000;
    final seconds = (totalCentis % 6000) / 100;
    return '$minutes:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  }
}

/// Shows the structure preview. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricStructureDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  ValueChanged<int>? onPreviewLine,
  LyricStructureAdvisor advisor = const LyricStructureAdvisor(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricStructureDialog(
      document: document,
      protectedIndices: protectedIndices,
      onPreviewLine: onPreviewLine,
      advisor: advisor,
    ),
  );
}

class LyricStructureDialog extends StatefulWidget {
  const LyricStructureDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.onPreviewLine,
    this.advisor = const LyricStructureAdvisor(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;

  /// Plays a row so a guessed break can be checked by ear.
  final ValueChanged<int>? onPreviewLine;
  final LyricStructureAdvisor advisor;

  /// How many suggestions the preview lists before summarising the rest.
  static const int previewLimit = 60;

  @override
  State<LyricStructureDialog> createState() => _LyricStructureDialogState();
}

class _LyricStructureDialogState extends State<LyricStructureDialog> {
  late final LyricStructurePlan _plan;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _plan = widget.advisor.analyze(
      widget.document,
      protectedIndices: widget.protectedIndices,
    );
    for (var i = 0; i < _plan.suggestions.length; i++) {
      if (_plan.suggestions[i].confident) _selected.add(i);
    }
  }

  int _countSelected(LyricStructureSuggestionKind kind) => _selected
      .where((position) => _plan.suggestions[position].kind == kind)
      .length;

  void _confirm() {
    if (_selected.isEmpty) return;
    final splits = _countSelected(LyricStructureSuggestionKind.splitLongLine);
    final merges = _countSelected(LyricStructureSuggestionKind.mergeFragment);
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: _plan.applyTo(widget.document, _selected),
        label: LyricStructureStrings.actionTitle,
        message: LyricStructureStrings.applied(splits, merges),
        selectedLineIndex: _plan.selectionAfterApply(_selected),
      ),
    );
  }

  void _setAll(bool value) => setState(() {
    _selected.clear();
    if (value) {
      _selected.addAll(List.generate(_plan.suggestions.length, (i) => i));
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final splits = _countSelected(LyricStructureSuggestionKind.splitLongLine);
    final merges = _countSelected(LyricStructureSuggestionKind.mergeFragment);
    final skipped = plan.skippedProtectedIndices.length;
    final visible = plan.suggestions.length.clamp(
      0,
      LyricStructureDialog.previewLimit,
    );

    return LyricBatchEditDialogFrame(
      title: LyricStructureStrings.actionTitle,
      confirmKey: const ValueKey('structure_confirm'),
      confirmIcon: Icons.view_agenda_outlined,
      confirmLabel: _selected.isEmpty
          ? (plan.isEmpty ? '无需整理' : '请选择要应用的建议')
          : [
              if (splits > 0) '拆分 $splits 行',
              if (merges > 0) '合并 $merges 处',
            ].join('、'),
      onConfirm: _selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricStructureStrings.intro),
        if (skipped > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          LyricBatchNote('另有 $skipped 行手动编辑过，已跳过；需要时可在检查器里逐行拆分或合并。'),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                plan.isEmpty
                    ? '没有发现过长或被切碎的行。'
                    : '发现 ${plan.splitCount} 行过长、${plan.mergeCount} 处碎片行：',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (!plan.isEmpty)
              TextButton(
                key: const ValueKey('structure_toggle_all'),
                onPressed: () =>
                    _setAll(_selected.length != plan.suggestions.length),
                child: Text(
                  _selected.length == plan.suggestions.length ? '全不选' : '全选',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var position = 0; position < visible; position++)
          _SuggestionRow(
            key: ValueKey('structure_suggestion_$position'),
            suggestion: plan.suggestions[position],
            selected: _selected.contains(position),
            onSelectedChanged: (value) => setState(
              () => value
                  ? _selected.add(position)
                  : _selected.remove(position),
            ),
            onPreview: widget.onPreviewLine == null
                ? null
                : () => widget.onPreviewLine!(
                    plan.suggestions[position].index,
                  ),
          ),
        if (plan.suggestions.length > visible)
          LyricBatchNote(
            '另有 ${plan.suggestions.length - visible} 条建议未列出，'
            '它们保持当前勾选状态。',
          ),
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    super.key,
    required this.suggestion,
    required this.selected,
    required this.onSelectedChanged,
    required this.onPreview,
  });

  final LyricStructureSuggestion suggestion;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LyricBatchChangeRow(
            index: suggestion.index,
            before: suggestion.before.join(' ⏎ '),
            after: suggestion.after.join('\n'),
            note: LyricStructureStrings.note(suggestion),
            selected: selected,
            onSelectedChanged: onSelectedChanged,
          ),
        ),
        if (onPreview != null)
          IconButton(
            tooltip: '试听第 ${suggestion.index + 1} 行',
            onPressed: onPreview,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
      ],
    );
  }
}
