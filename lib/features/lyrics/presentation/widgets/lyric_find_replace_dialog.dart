import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_find_replace_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the find-and-replace tool.
class LyricFindReplaceStrings {
  const LyricFindReplaceStrings._();

  static const String actionTitle = '批量查找替换';
  static const String actionDetail = '同一个词识别错多次时一次改完；先预览，可逐行取消';
  static const String intro =
      '在全部歌词中查找并替换文字，只改文字不改时间轴。替换后的行会视为手动编辑，'
      '之后的智能校对不会再覆盖它们。结果可撤销，保存后才写盘。';

  static String noop(LyricFindReplaceNoopReason reason) => switch (reason) {
    LyricFindReplaceNoopReason.emptyQuery => '输入要查找的文字。',
    LyricFindReplaceNoopReason.noMatches => '没有找到匹配的歌词。',
    LyricFindReplaceNoopReason.replacementIdentical => '匹配处已经和替换文字相同，无需替换。',
    LyricFindReplaceNoopReason.onlyProtectedLines =>
      '匹配的行都被手动编辑过，默认跳过；勾选“同时替换手动编辑过的行”后可替换。',
  };

  static String applied(int lines, int occurrences) =>
      '已在 $lines 行中替换 $occurrences 处（未写入磁盘）';
}

/// Shows the find-and-replace tool. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricFindReplaceDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  String initialQuery = '',
  LyricFindReplaceService service = const LyricFindReplaceService(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricFindReplaceDialog(
      document: document,
      protectedIndices: protectedIndices,
      initialQuery: initialQuery,
      service: service,
    ),
  );
}

class LyricFindReplaceDialog extends StatefulWidget {
  const LyricFindReplaceDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.initialQuery = '',
    this.service = const LyricFindReplaceService(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final String initialQuery;
  final LyricFindReplaceService service;

  /// How many matched rows are listed before the rest are summarised.
  static const int previewLimit = 30;

  @override
  State<LyricFindReplaceDialog> createState() => _LyricFindReplaceDialogState();
}

class _LyricFindReplaceDialogState extends State<LyricFindReplaceDialog> {
  late final TextEditingController _find;
  final TextEditingController _replace = TextEditingController();
  bool _ignoreScript = true;
  bool _ignoreCase = true;
  bool _wholeWord = false;
  bool _includeProtected = false;
  final Set<int> _excluded = <int>{};
  late LyricFindReplacePlan _plan;

  @override
  void initState() {
    super.initState();
    _find = TextEditingController(text: widget.initialQuery);
    _plan = _buildPlan();
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  LyricFindReplacePlan _buildPlan() => widget.service.plan(
    widget.document,
    query: LyricFindReplaceQuery(
      find: _find.text,
      replacement: _replace.text,
      ignoreChineseScript: _ignoreScript,
      ignoreCase: _ignoreCase,
      wholeWord: _wholeWord,
    ),
    protectedIndices: widget.protectedIndices,
    includeProtected: _includeProtected,
  );

  void _update(VoidCallback change, {bool resetExclusions = true}) {
    setState(() {
      change();
      // A new query matches different rows; stale opt-outs would silently
      // skip rows the user never saw unticked.
      if (resetExclusions) _excluded.clear();
      _plan = _buildPlan();
    });
  }

  void _confirm() {
    final plan = _plan;
    final selected = plan.selectedChanges(_excluded);
    if (selected.isEmpty) return;
    final occurrences = selected.fold<int>(
      0,
      (total, match) => total + match.occurrences,
    );
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: plan.applyTo(widget.document, excludedIndices: _excluded),
        label:
            '${LyricFindReplaceStrings.actionTitle}：'
            '“${plan.query.find}” → “${plan.query.replacement}”',
        message: LyricFindReplaceStrings.applied(selected.length, occurrences),
        selectedLineIndex: selected.first.index,
        manuallyEditedLineIds: {
          for (final match in selected)
            if (match.lineId != null) match.lineId!,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final selected = plan.selectedChanges(_excluded);
    final protectedCount = _includeProtected
        ? plan.matches
              .where(
                (match) =>
                    match.changesText &&
                    widget.protectedIndices.contains(match.index),
              )
              .length
        : plan.protectedMatches.length;
    final listed = plan.matches.take(LyricFindReplaceDialog.previewLimit);

    return LyricBatchEditDialogFrame(
      title: LyricFindReplaceStrings.actionTitle,
      confirmKey: const ValueKey('find_replace_confirm'),
      confirmIcon: Icons.find_replace_rounded,
      confirmLabel: selected.isEmpty ? '无可替换' : '替换 ${selected.length} 行',
      onConfirm: selected.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricFindReplaceStrings.intro),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('find_replace_find_field'),
          controller: _find,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '查找',
            hintText: '例如识别错的词：我碍你',
          ),
          onChanged: (_) => _update(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('find_replace_replacement_field'),
          controller: _replace,
          decoration: const InputDecoration(
            labelText: '替换为',
            hintText: '留空表示删除匹配的文字',
          ),
          onChanged: (_) => _update(() {}, resetExclusions: false),
          onSubmitted: (_) {
            if (_plan.selectedChanges(_excluded).isNotEmpty) _confirm();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            FilterChip(
              label: const Text('忽略简繁差异'),
              selected: _ignoreScript,
              onSelected: (value) => _update(() => _ignoreScript = value),
            ),
            FilterChip(
              label: const Text('忽略英文大小写'),
              selected: _ignoreCase,
              onSelected: (value) => _update(() => _ignoreCase = value),
            ),
            FilterChip(
              label: const Text('英文全词匹配'),
              selected: _wholeWord,
              onSelected: (value) => _update(() => _wholeWord = value),
            ),
          ],
        ),
        if (protectedCount > 0 || _includeProtected)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeProtected,
            onChanged: (value) =>
                _update(() => _includeProtected = value ?? false),
            title: const Text('同时替换手动编辑过的行'),
            subtitle: Text('涉及 $protectedCount 行；默认跳过，避免覆盖手工修改'),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (plan.noopReason != null && selected.isEmpty)
          Text(
            LyricFindReplaceStrings.noop(plan.noopReason!),
            style: theme.textTheme.bodyMedium,
          )
        else
          Text(
            '找到 ${plan.matches.length} 行、${plan.totalOccurrences} 处匹配；'
            '将替换 ${selected.length} 行。',
            style: theme.textTheme.titleSmall,
          ),
        const SizedBox(height: AppSpacing.xs),
        for (final match in listed)
          LyricBatchChangeRow(
            key: ValueKey('find_replace_row_${match.index}'),
            index: match.index,
            before: match.before,
            after: match.changesText ? match.after : null,
            note: match.isProtected
                ? '手动编辑过，已跳过'
                : !match.changesText
                ? '已是替换后的文字'
                : '${match.occurrences} 处',
            highlights: [
              for (final range in match.ranges) (range.start, range.end),
            ],
            selected:
                !match.isProtected &&
                match.changesText &&
                !_excluded.contains(match.index),
            onSelectedChanged: match.isProtected || !match.changesText
                ? null
                : (value) => _update(
                    () => value
                        ? _excluded.remove(match.index)
                        : _excluded.add(match.index),
                    resetExclusions: false,
                  ),
          ),
        if (plan.matches.length > LyricFindReplaceDialog.previewLimit)
          LyricBatchNote(
            '另有 ${plan.matches.length - LyricFindReplaceDialog.previewLimit} 行'
            '未列出，确认后同样会替换。',
          ),
      ],
    );
  }
}
