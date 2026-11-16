import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/character_diff_service.dart';
import '../../domain/services/lyric_repetition_consistency_service.dart';
import 'lyric_batch_text_edit.dart';

/// User-facing text of the repeated-line consistency check.
class LyricRepetitionStrings {
  const LyricRepetitionStrings._();

  static const String actionTitle = '重复段落一致性检查';
  static const String actionDetail = '不需要参考歌词；副歌等重复行识别不一致时，按多数写法统一';
  static const String intro =
      '副歌、重复句在不同位置往往被识别成不同的字。这里把几乎相同的行归为一组，'
      '建议统一为出现次数最多或你手动确认过的写法。只改文字，不改时间轴；'
      '各组可单独选择写法或不统一。结果可撤销，保存后才写盘。';
  static const String nothingFound = '没有发现写法不一致的重复行。';

  static String recommendation(LyricRepetitionGroup group) =>
      switch (group.recommendation) {
        LyricRepetitionRecommendation.majority => '按出现次数推荐',
        LyricRepetitionRecommendation.manuallyConfirmed => '你手动确认过其中一种写法',
        LyricRepetitionRecommendation.higherConfidence =>
          '出现次数相同，按识别置信度推荐，请试听确认',
        LyricRepetitionRecommendation.undecided => '无法判断哪种写法正确，请试听后选择',
      };

  static String rows(List<int> indices) {
    const shown = 6;
    final labels = [for (final index in indices.take(shown)) '${index + 1}'];
    final more = indices.length > shown ? ' 等 ${indices.length} 行' : '';
    return '第 ${labels.join('、')} 行$more';
  }

  static String applied(int rows, int groups) =>
      '已统一 $groups 组重复行，共修改 $rows 行（未写入磁盘）';
}

/// Shows the consistency check for [document]. Returns the confirmed edit or
/// null when cancelled or when there is nothing to unify.
Future<LyricBatchTextEdit?> showLyricRepetitionConsistencyDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  LyricRepetitionConsistencyService service =
      const LyricRepetitionConsistencyService(),
  void Function(int index)? onPreviewLine,
}) {
  return showDialog<LyricBatchTextEdit>(
    context: context,
    builder: (_) => LyricRepetitionConsistencyDialog(
      document: document,
      protectedIndices: protectedIndices,
      service: service,
      onPreviewLine: onPreviewLine,
    ),
  );
}

class LyricRepetitionConsistencyDialog extends StatefulWidget {
  const LyricRepetitionConsistencyDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    this.service = const LyricRepetitionConsistencyService(),
    this.onPreviewLine,
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final LyricRepetitionConsistencyService service;

  /// Plays a row so the user can hear which spelling is right.
  final void Function(int index)? onPreviewLine;

  @override
  State<LyricRepetitionConsistencyDialog> createState() =>
      _LyricRepetitionConsistencyDialogState();
}

class _LyricRepetitionConsistencyDialogState
    extends State<LyricRepetitionConsistencyDialog> {
  late final LyricRepetitionReport _report;

  /// Chosen spelling per group; absent when the user has not chosen one.
  final Map<int, int> _choices = <int, int>{};
  final Set<int> _enabled = <int>{};
  bool _includeProtected = false;

  @override
  void initState() {
    super.initState();
    _report = widget.service.analyze(
      widget.document,
      protectedIndices: widget.protectedIndices,
    );
    for (var i = 0; i < _report.groups.length; i++) {
      final group = _report.groups[i];
      final recommended = group.recommendedVariant;
      if (recommended != null) _choices[i] = recommended;
      if (group.selectedByDefault) _enabled.add(i);
    }
  }

  Map<int, int> get _activeChoices => {
    for (final entry in _choices.entries)
      if (_enabled.contains(entry.key)) entry.key: entry.value,
  };

  List<LyricRepetitionChange> get _changes => _report.changesFor(
    widget.document,
    _activeChoices,
    includeProtected: _includeProtected,
  );

  bool get _hasProtectedOutliers {
    for (final entry in _activeChoices.entries) {
      final group = _report.groups[entry.key];
      for (var v = 0; v < group.variants.length; v++) {
        if (v != entry.value && group.variants[v].hasProtectedRows) return true;
      }
    }
    return false;
  }

  void _confirm() {
    final changes = _changes;
    if (changes.isEmpty) return;
    final groups = {
      for (final entry in _activeChoices.entries)
        if (_groupChanges(entry.key, changes)) entry.key,
    }.length;
    Navigator.of(context).pop(
      LyricBatchTextEdit(
        document: LyricRepetitionReport.apply(widget.document, changes),
        label: LyricRepetitionStrings.actionTitle,
        message: LyricRepetitionStrings.applied(changes.length, groups),
        selectedLineIndex: changes.first.index,
        manuallyEditedLineIds: {
          for (final change in changes)
            if (change.lineId != null) change.lineId!,
        },
      ),
    );
  }

  bool _groupChanges(int groupIndex, List<LyricRepetitionChange> changes) {
    final rows = {
      for (final variant in _report.groups[groupIndex].variants)
        ...variant.indices,
    };
    return changes.any((change) => rows.contains(change.index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = _changes;
    return LyricBatchEditDialogFrame(
      title: LyricRepetitionStrings.actionTitle,
      confirmKey: const ValueKey('repetition_confirm'),
      confirmIcon: Icons.library_add_check_rounded,
      confirmLabel: changes.isEmpty ? '无需统一' : '统一 ${changes.length} 行',
      onConfirm: changes.isEmpty ? null : _confirm,
      children: [
        const LyricBatchNote(LyricRepetitionStrings.intro),
        const SizedBox(height: AppSpacing.md),
        if (!_report.hasGroups)
          Text(
            LyricRepetitionStrings.nothingFound,
            style: theme.textTheme.bodyMedium,
          )
        else ...[
          Text(
            '发现 ${_report.groups.length} 组写法不一致的重复行；'
            '已选 ${_activeChoices.length} 组，将修改 ${changes.length} 行。',
            style: theme.textTheme.titleSmall,
          ),
          if (_hasProtectedOutliers || _includeProtected)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeProtected,
              onChanged: (value) =>
                  setState(() => _includeProtected = value ?? false),
              title: const Text('同时修改手动编辑过的行'),
              subtitle: const Text('默认跳过，避免覆盖手工修改'),
            ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < _report.groups.length; i++)
            _GroupCard(
              key: ValueKey('repetition_group_$i'),
              group: _report.groups[i],
              enabled: _enabled.contains(i),
              choice: _choices[i],
              onEnabledChanged: (value) => setState(() {
                if (value && _choices[i] != null) {
                  _enabled.add(i);
                } else {
                  _enabled.remove(i);
                }
              }),
              onChoose: (variant) => setState(() {
                _choices[i] = variant;
                _enabled.add(i);
              }),
              onPreviewLine: widget.onPreviewLine,
            ),
        ],
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.enabled,
    required this.choice,
    required this.onEnabledChanged,
    required this.onChoose,
    required this.onPreviewLine,
  });

  final LyricRepetitionGroup group;
  final bool enabled;
  final int? choice;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onChoose;
  final void Function(int index)? onPreviewLine;

  static const CharacterDiffService _diff = CharacterDiffService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = choice == null ? null : group.variants[choice!];
    return Card(
      color: AppColors.bgSurface,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: enabled,
              onChanged: choice == null
                  ? null
                  : (value) => onEnabledChanged(value ?? false),
              title: Text(
                target == null ? '先选择一种写法' : '统一为“${target.text}”',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                '${group.totalRows} 行 · ${LyricRepetitionStrings.recommendation(group)}',
              ),
            ),
            for (var v = 0; v < group.variants.length; v++)
              _variantRow(context, v, target),
          ],
        ),
      ),
    );
  }

  Widget _variantRow(
    BuildContext context,
    int v,
    LyricRepetitionVariant? target,
  ) {
    final theme = Theme.of(context);
    final variant = group.variants[v];
    final isTarget = choice == v;
    final segments = target == null || isTarget
        ? null
        : _diff.diff(target.text, variant.text);
    final label = segments == null
        ? Text(variant.text)
        : Text.rich(
            TextSpan(
              children: [
                for (final segment in segments)
                  if (segment.type != CharacterDiffType.delete)
                    TextSpan(
                      text: segment.text,
                      style: segment.isEqual
                          ? null
                          : const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                    ),
              ],
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChoiceChip(
                  key: ValueKey('repetition_variant_${variant.indices.first}'),
                  label: label,
                  selected: isTarget,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => onChoose(v),
                ),
                Text(
                  [
                    '×${variant.count}',
                    LyricRepetitionStrings.rows(variant.indices),
                    if (variant.hasProtectedRows) '含手动编辑',
                    if (variant.meanConfidence != null)
                      '置信度 ${variant.meanConfidence!.round()}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (onPreviewLine != null)
            IconButton(
              tooltip: '试听第 ${variant.indices.first + 1} 行',
              onPressed: () => onPreviewLine!(variant.indices.first),
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
        ],
      ),
    );
  }
}
