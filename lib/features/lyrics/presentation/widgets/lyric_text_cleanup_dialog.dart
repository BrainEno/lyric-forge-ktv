import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_text_cleanup_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the recognised-text clean-up tool.
class LyricTextCleanupStrings {
  const LyricTextCleanupStrings._();

  static const String actionTitle = '清理识别文本';
  static const String actionDetail = '不需要参考歌词；去掉标点、[音乐] 标记和字幕水印等识别残留';
  static const String intro =
      '去掉识别结果中不属于歌词的内容：句末标点、全角字母、[音乐] 之类的标注，'
      '以及识别器在静音处编造的字幕水印。只改写法，不改时间轴；'
      '删除整行会一并删掉该行的时间。结果可撤销，保存后才写盘。';

  static String rule(LyricTextCleanupRule rule) => switch (rule) {
    LyricTextCleanupRule.normalizeWhitespace => '整理多余空格',
    LyricTextCleanupRule.fullWidthAscii => '全角字母数字转半角',
    LyricTextCleanupRule.stripAnnotations => '去掉 [音乐]、(Music)、♪ 等标注',
    LyricTextCleanupRule.internalPunctuationToSpace => '句中标点改为空格',
    LyricTextCleanupRule.trailingPunctuation => '去掉句末标点（保留 ？！）',
    LyricTextCleanupRule.removeCjkSpaces => '去掉汉字之间的空格',
    LyricTextCleanupRule.removeAsrBoilerplate => '删除字幕水印行（谢谢观看等）',
    LyricTextCleanupRule.removeAnnotationOnlyLines => '删除只有标注的行',
    LyricTextCleanupRule.removeEmptyLines => '删除空行',
  };

  static String? ruleHelp(LyricTextCleanupRule rule) => switch (rule) {
    LyricTextCleanupRule.removeCjkSpaces => '很多歌词用空格分隔乐句，默认不开启',
    LyricTextCleanupRule.removeEmptyLines => '空行可能是刻意留出的间隔，默认不开启',
    _ => null,
  };

  static String applied(int changed, int removed) {
    final parts = [
      if (changed > 0) '清理 $changed 行',
      if (removed > 0) '删除 $removed 行',
    ];
    return '已${parts.join('、')}（未写入磁盘）';
  }
}

/// Shows the clean-up preview. Returns the confirmed edit, or null.
Future<LyricBatchTextEdit?> showLyricTextCleanupDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  LyricTextCleanupService service = const LyricTextCleanupService(),
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricTextCleanupDialog(
      document: document,
      protectedIndices: protectedIndices,
      service: service,
    ),
  );
}

class LyricTextCleanupDialog extends StatefulWidget {
  const LyricTextCleanupDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.service = const LyricTextCleanupService(),
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final LyricTextCleanupService service;

  /// How many rows the preview lists before summarising the rest.
  static const int previewLimit = 40;

  @override
  State<LyricTextCleanupDialog> createState() => _LyricTextCleanupDialogState();
}

class _LyricTextCleanupDialogState extends State<LyricTextCleanupDialog> {
  final Set<LyricTextCleanupRule> _rules = {...LyricTextCleanupRule.defaults};
  bool _includeProtected = false;
  late LyricTextCleanupPlan _plan;

  /// Counts with every rule on, so a switched-off rule can still say how many
  /// rows it would touch.
  late final Map<LyricTextCleanupRule, int> _potentialCounts;

  @override
  void initState() {
    super.initState();
    _plan = _buildPlan();
    _potentialCounts = widget.service
        .plan(
          widget.document,
          rules: LyricTextCleanupRule.values.toSet(),
          protectedIndices: widget.protectedIndices,
        )
        .countsByRule;
  }

  LyricTextCleanupPlan _buildPlan() => widget.service.plan(
    widget.document,
    rules: _rules,
    protectedIndices: _includeProtected ? const {} : widget.protectedIndices,
  );

  void _update(VoidCallback change) {
    setState(() {
      change();
      _plan = _buildPlan();
    });
  }

  void _confirm() {
    final plan = _plan;
    if (!plan.hasChanges) return;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: plan.applyTo(widget.document),
        label: LyricTextCleanupStrings.actionTitle,
        message: LyricTextCleanupStrings.applied(
          plan.changes.length,
          plan.removals.length,
        ),
        selectedLineIndex: plan.selectionAfterApply(
          widget.document.lines.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final counts = plan.countsByRule;
    final protectedSkipped = plan.skippedProtectedIndices.length;
    final rows = <({int index, Widget row})>[
      for (final change in plan.changes)
        (
          index: change.index,
          row: LyricBatchChangeRow(
            key: ValueKey('cleanup_change_${change.index}'),
            index: change.index,
            before: change.before,
            after: change.after,
            note: change.rules.map(LyricTextCleanupStrings.rule).join('，'),
          ),
        ),
      for (final removal in plan.removals)
        (
          index: removal.index,
          row: LyricBatchChangeRow(
            key: ValueKey('cleanup_removal_${removal.index}'),
            index: removal.index,
            before: removal.text,
            after: null,
            removal: true,
            note: LyricTextCleanupStrings.rule(removal.rule),
          ),
        ),
    ]..sort((a, b) => a.index.compareTo(b.index));
    final total = rows.length;

    return LyricBatchEditDialogFrame(
      title: LyricTextCleanupStrings.actionTitle,
      confirmKey: const ValueKey('cleanup_confirm'),
      confirmIcon: Icons.cleaning_services_rounded,
      confirmLabel: plan.hasChanges
          ? [
              if (plan.changes.isNotEmpty) '清理 ${plan.changes.length} 行',
              if (plan.removals.isNotEmpty) '删除 ${plan.removals.length} 行',
            ].join('、')
          : '无需清理',
      onConfirm: plan.hasChanges ? _confirm : null,
      children: [
        const LyricBatchNote(LyricTextCleanupStrings.intro),
        const SizedBox(height: AppSpacing.sm),
        for (final rule in LyricTextCleanupRule.values)
          CheckboxListTile(
            key: ValueKey('cleanup_rule_${rule.name}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _rules.contains(rule),
            onChanged: (value) => _update(
              () => value ?? false ? _rules.add(rule) : _rules.remove(rule),
            ),
            title: Text(LyricTextCleanupStrings.rule(rule)),
            subtitle: Text(
              [
                _rules.contains(rule)
                    ? '${counts[rule] ?? 0} 行'
                    : '可处理 ${_potentialCounts[rule] ?? 0} 行',
                ?LyricTextCleanupStrings.ruleHelp(rule),
              ].join(' · '),
            ),
          ),
        if (protectedSkipped > 0 || _includeProtected)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeProtected,
            onChanged: (value) =>
                _update(() => _includeProtected = value ?? false),
            title: const Text('同时清理手动编辑过的行'),
            subtitle: Text(
              _includeProtected
                  ? '手动编辑过的行也会被清理'
                  : '跳过 $protectedSkipped 行；默认不改动手工修改',
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          plan.hasChanges
              ? '将清理 ${plan.changes.length} 行、删除 ${plan.removals.length} 行：'
              : '按当前规则没有需要清理的行。',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final entry in rows.take(LyricTextCleanupDialog.previewLimit))
          entry.row,
        if (total > LyricTextCleanupDialog.previewLimit)
          LyricBatchNote(
            '另有 ${total - LyricTextCleanupDialog.previewLimit} 行未列出，'
            '确认后同样会处理。',
          ),
      ],
    );
  }
}
