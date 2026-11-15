import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/chinese_script_preference.dart';
import '../../domain/services/chinese_script_unification_service.dart';
import '../../domain/text/chinese_script_converter.dart';

/// User-facing names for the script preference, shared by the editor action
/// and the recognition settings.
class ChineseScriptStrings {
  const ChineseScriptStrings._();

  static const String settingLabel = '中文字形';
  static const String settingHelp =
      '识别结果简繁混杂时如何处理。只改字形不改用词；日文、韩文行不转换；'
      '比较与校对始终忽略简繁差异。';
  static const String actionTitle = '统一简繁字形';
  static const String approximateNote =
      '简体转繁体按 OpenCC 词典逐词匹配，「发/發/髮」这类一对多的字可能选错，请逐行核对。';

  static String preference(ChineseScriptPreference value) => switch (value) {
    ChineseScriptPreference.auto => '自动（统一少数派行）',
    ChineseScriptPreference.keep => '保持原样',
    ChineseScriptPreference.simplified => '简体',
    ChineseScriptPreference.traditionalTaiwan => '繁體（台灣）',
    ChineseScriptPreference.traditionalHongKong => '繁體（香港）',
  };

  static String target(ChineseScriptTarget value) =>
      preference(ChineseScriptPreference.forTarget(value));

  static String noop(ChineseScriptNoopReason reason) => switch (reason) {
    ChineseScriptNoopReason.disabled => '已选择保持原样，不会修改歌词。',
    ChineseScriptNoopReason.notChinese => '当前歌词不是中文（或主要是日文/韩文），不做字形转换。',
    ChineseScriptNoopReason.noChineseText => '歌词中没有汉字，无需转换。',
    ChineseScriptNoopReason.alreadyConsistent => '字形已经统一，没有需要修改的行。',
    ChineseScriptNoopReason.ambiguousMajority =>
      '简体行与繁体行数量相同，无法自动判断目标字形，请直接选择简体或繁體。',
    ChineseScriptNoopReason.onlyProtectedLines => '需要转换的行都被手动编辑过，已按默认设置跳过。',
  };
}

/// Shows the unification preview and returns the plan the user confirmed, or
/// null when cancelled. Nothing is written: the caller applies the plan to
/// the editing document as one undoable change.
Future<ChineseScriptUnificationPlan?> showChineseScriptUnificationDialog(
  BuildContext context, {
  required LyricDocument document,
  required Set<int> protectedIndices,
  ChineseScriptPreference initialPreference = ChineseScriptPreference.auto,
  ChineseScriptUnificationService service =
      const ChineseScriptUnificationService(),
}) {
  return showDialog<ChineseScriptUnificationPlan>(
    context: context,
    builder: (_) => ChineseScriptUnificationDialog(
      document: document,
      protectedIndices: protectedIndices,
      initialPreference: initialPreference,
      service: service,
    ),
  );
}

/// The preference the dialog opens with: the target of the last recorded
/// unification, so repeating the action keeps the user's choice.
ChineseScriptPreference initialChineseScriptPreferenceFor(
  LyricDocument document,
) {
  final record = ChineseScriptUnificationRecord.tryParse(
    document.metadata[ChineseScriptUnificationService.metadataKey],
  );
  return record == null
      ? ChineseScriptPreference.auto
      : ChineseScriptPreference.forTarget(record.target);
}

class ChineseScriptUnificationDialog extends StatefulWidget {
  const ChineseScriptUnificationDialog({
    super.key,
    required this.document,
    required this.protectedIndices,
    required this.initialPreference,
    required this.service,
  });

  final LyricDocument document;
  final Set<int> protectedIndices;
  final ChineseScriptPreference initialPreference;
  final ChineseScriptUnificationService service;

  /// How many changed lines the preview lists before summarising the rest.
  static const int previewLimit = 6;

  @override
  State<ChineseScriptUnificationDialog> createState() =>
      _ChineseScriptUnificationDialogState();
}

class _ChineseScriptUnificationDialogState
    extends State<ChineseScriptUnificationDialog> {
  static const List<ChineseScriptPreference> _choices = [
    ChineseScriptPreference.auto,
    ChineseScriptPreference.simplified,
    ChineseScriptPreference.traditionalTaiwan,
    ChineseScriptPreference.traditionalHongKong,
  ];

  late ChineseScriptPreference _preference;
  bool _includeProtected = false;
  late ChineseScriptUnificationPlan _plan;

  @override
  void initState() {
    super.initState();
    _preference = _choices.contains(widget.initialPreference)
        ? widget.initialPreference
        : ChineseScriptPreference.auto;
    _plan = _buildPlan();
  }

  ChineseScriptUnificationPlan _buildPlan() => widget.service.plan(
    widget.document,
    preference: _preference,
    protectedIndices: _includeProtected ? const {} : widget.protectedIndices,
  );

  void _update(VoidCallback change) {
    setState(() {
      change();
      _plan = _buildPlan();
    });
  }

  /// Protected lines that would change if the user opted in, computed without
  /// protection so the checkbox can say how many lines it affects.
  int get _protectedCandidates {
    if (_includeProtected) {
      return _plan.changes
          .where((change) => widget.protectedIndices.contains(change.index))
          .length;
    }
    return _plan.skippedProtectedIndices.length;
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final maxWidth = spec.isCompact ? 520.0 : 600.0;
    final maxHeight =
        (media.size.height -
                media.viewInsets.bottom -
                spec.pageGutter * 2 -
                160)
            .clamp(240.0, 560.0)
            .toDouble();
    final plan = _plan;
    final target = plan.target;
    final protectedCandidates = _protectedCandidates;

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      titlePadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        spec.pageGutter,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        0,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        spec.pageGutter,
      ),
      title: const Text(ChineseScriptStrings.actionTitle),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '只改变字的写法（爱/愛、里/裡），不改用词与时间轴。'
                '结果写入编辑中的歌词，可撤销，保存后才写盘。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final choice in _choices)
                    ChoiceChip(
                      label: Text(ChineseScriptStrings.preference(choice)),
                      selected: _preference == choice,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => _update(() => _preference = choice),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ProfileSummary(profile: plan.profile),
              if (protectedCandidates > 0 || _includeProtected)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeProtected,
                  onChanged: (value) =>
                      _update(() => _includeProtected = value ?? false),
                  title: const Text('同时转换手动编辑过的行'),
                  subtitle: Text('涉及 $protectedCandidates 行；默认跳过，避免覆盖手工修改'),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (plan.hasChanges && target != null) ...[
                Text(
                  '将把 ${plan.changes.length} 行转换为'
                  '${ChineseScriptStrings.target(target)}：',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final change in plan.changes.take(
                  ChineseScriptUnificationDialog.previewLimit,
                ))
                  _ChangePreview(change: change),
                if (plan.changes.length >
                    ChineseScriptUnificationDialog.previewLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '另有 ${plan.changes.length - ChineseScriptUnificationDialog.previewLimit} 行未列出',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                if (target.isTraditional) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    ChineseScriptStrings.approximateNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ] else if (plan.noopReason != null)
                Text(
                  ChineseScriptStrings.noop(plan.noopReason!),
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: plan.hasChanges
              ? () => Navigator.of(context).pop(plan)
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          icon: const Icon(Icons.translate_rounded, size: 18),
          label: Text(plan.hasChanges ? '转换 ${plan.changes.length} 行' : '无需转换'),
        ),
      ],
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final ChineseScriptDocumentProfile profile;

  @override
  Widget build(BuildContext context) {
    final parts = [
      '简体 ${profile.simplifiedLines} 行',
      '繁体 ${profile.traditionalLines} 行',
      if (profile.mixedLines > 0) '简繁混用 ${profile.mixedLines} 行',
      '通用 ${profile.neutralLines} 行',
      if (profile.japaneseOrKoreanLines > 0)
        '日文/韩文 ${profile.japaneseOrKoreanLines} 行（不转换）',
    ];
    return Text(
      '当前：${parts.join('，')}',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _ChangePreview extends StatelessWidget {
  const _ChangePreview({required this.change});

  final ChineseScriptLineChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${change.index + 1} 行',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          Text(
            change.before,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(change.after, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
