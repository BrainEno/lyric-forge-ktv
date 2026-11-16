import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import 'lyric_find_replace_dialog.dart';
import 'lyric_pace_check_dialog.dart';
import 'lyric_repetition_consistency_dialog.dart';
import 'lyric_structure_dialog.dart';
import 'lyric_tap_sync_dialog.dart';
import 'lyric_text_cleanup_dialog.dart';
import 'lyric_timeline_repair_dialog.dart';
import 'lyric_timing_shift_dialog.dart';

/// The proofreading capabilities, in the order they are offered.
///
/// Generation actions come first because they are what the user came for;
/// reviewing and rolling back the last result sits behind a divider so the
/// destructive-sounding entries are not the first thing under the cursor.
enum LyricProofreadAction {
  proofreadV2,
  referenceAlignment,
  referenceProofread,
  repetitionConsistency,
  textCleanup,
  lineStructure,
  timelineRepair,
  paceCheck,
  timingShift,
  tapSync,
  unifyChineseScript,
  findReplace,
  viewComparison,
  undoAlignment,
  restoreBackup,
}

/// One entry point for every proofreading flow.
///
/// The editor used to expose four to six separate buttons for this, each with a
/// label the user had to decode before understanding the difference. The flows
/// themselves are unchanged; only the entry point is now a single menu, so the two
/// distinct strategies (with and without reference lyrics) are described next to
/// each other instead of hidden in different corners of the toolbar.
class LyricProofreadMenuButton extends StatelessWidget {
  const LyricProofreadMenuButton({
    super.key,
    this.onProofreadV2,
    this.onReferenceAlignment,
    this.onReferenceProofread,
    this.onUnifyChineseScript,
    this.onRepetitionConsistency,
    this.onTextCleanup,
    this.onLineStructure,
    this.onTimelineRepair,
    this.onTimingShift,
    this.onPaceCheck,
    this.onTapSync,
    this.onFindReplace,
    this.onViewComparison,
    this.onUndoAlignment,
    this.onRestoreBackup,
    this.compact = false,
  });

  /// 智能校对 V2: builds a proposal from the ASR evidence without writing it.
  final VoidCallback? onProofreadV2;

  /// 参考歌词纠正: aligns a pasted reference and can replace timing.
  final VoidCallback? onReferenceAlignment;

  /// 逐行智能纠错: text-only corrections from a pasted reference.
  final VoidCallback? onReferenceProofread;

  /// 统一简繁字形: previews and applies a simplified/traditional unification.
  final VoidCallback? onUnifyChineseScript;

  /// 重复段落一致性检查: unifies repeats (choruses) recognised differently.
  final VoidCallback? onRepetitionConsistency;

  /// 清理识别文本: strips punctuation, annotations and caption boilerplate.
  final VoidCallback? onTextCleanup;

  /// 整理断行: splits over-long rows and merges fragments.
  final VoidCallback? onLineStructure;

  /// 检查时间轴: repairs overlaps, missing ends and out-of-order starts.
  final VoidCallback? onTimelineRepair;

  /// 平移 / 伸缩时间轴: moves or stretches the timing of a range of rows.
  final VoidCallback? onTimingShift;

  /// Opens the pace check (语速异常检查).
  final VoidCallback? onPaceCheck;

  /// Opens tap-to-sync (打轴).
  final VoidCallback? onTapSync;

  /// 批量查找替换: replaces a misrecognised word everywhere at once.
  final VoidCallback? onFindReplace;

  final VoidCallback? onViewComparison;
  final VoidCallback? onUndoAlignment;
  final VoidCallback? onRestoreBackup;

  /// Icon-only variant for the app bar on narrow layouts.
  final bool compact;

  static const String label = '校对';

  @override
  Widget build(BuildContext context) {
    final items = _items();
    if (items.isEmpty) return const SizedBox.shrink();

    return MenuAnchor(
      menuChildren: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0 && items[index].startsNewGroup)
            const Divider(height: 1),
          MenuItemButton(
            onPressed: items[index].onPressed,
            leadingIcon: Icon(items[index].icon, size: 18),
            child: _MenuLabel(
              title: items[index].title,
              detail: items[index].detail,
            ),
          ),
        ],
      ],
      builder: (context, controller, child) {
        void open() {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        }

        if (compact) {
          return IconButton(
            tooltip: label,
            onPressed: open,
            icon: const Icon(Icons.spellcheck_rounded),
          );
        }
        return Tooltip(
          message: '校对：智能提案、参考歌词纠正、重复行统一、文本清理、整理断行、时间轴检查与平移、简繁统一、查找替换、逐行对比与回滚',
          child: FilledButton.tonalIcon(
            onPressed: open,
            icon: const Icon(Icons.spellcheck_rounded, size: 18),
            label: const Text(label),
          ),
        );
      },
    );
  }

  List<_ProofreadMenuItem> _items() {
    final actions = <LyricProofreadAction, VoidCallback?>{
      LyricProofreadAction.proofreadV2: onProofreadV2,
      LyricProofreadAction.referenceAlignment: onReferenceAlignment,
      LyricProofreadAction.referenceProofread: onReferenceProofread,
      LyricProofreadAction.repetitionConsistency: onRepetitionConsistency,
      LyricProofreadAction.textCleanup: onTextCleanup,
      LyricProofreadAction.lineStructure: onLineStructure,
      LyricProofreadAction.timelineRepair: onTimelineRepair,
      LyricProofreadAction.timingShift: onTimingShift,
      LyricProofreadAction.paceCheck: onPaceCheck,
      LyricProofreadAction.tapSync: onTapSync,
      LyricProofreadAction.unifyChineseScript: onUnifyChineseScript,
      LyricProofreadAction.findReplace: onFindReplace,
      LyricProofreadAction.viewComparison: onViewComparison,
      LyricProofreadAction.undoAlignment: onUndoAlignment,
      LyricProofreadAction.restoreBackup: onRestoreBackup,
    };

    final items = <_ProofreadMenuItem>[];
    for (final action in LyricProofreadAction.values) {
      final callback = actions[action];
      if (callback == null) continue;
      final text = _textFor(action);
      items.add(
        _ProofreadMenuItem(
          title: text.$1,
          detail: text.$2,
          icon: _iconFor(action),
          onPressed: callback,
          startsNewGroup:
              action == LyricProofreadAction.viewComparison && items.isNotEmpty,
        ),
      );
    }
    return items;
  }

  /// Title plus the one-line explanation that distinguishes the strategies.
  static (String, String?) _textFor(LyricProofreadAction action) {
    return switch (action) {
      LyricProofreadAction.proofreadV2 => (
        '智能校对 V2',
        '不需要参考歌词；生成不写盘的提案，逐行对比后再应用',
      ),
      LyricProofreadAction.referenceAlignment => ('参考歌词纠正', '有参考歌词；可一并修正时间轴'),
      LyricProofreadAction.referenceProofread => (
        '逐行智能纠错（保留时间戳）',
        '有参考歌词；只改文字，时间戳保持不变',
      ),
      LyricProofreadAction.repetitionConsistency => (
        LyricRepetitionStrings.actionTitle,
        LyricRepetitionStrings.actionDetail,
      ),
      LyricProofreadAction.textCleanup => (
        LyricTextCleanupStrings.actionTitle,
        LyricTextCleanupStrings.actionDetail,
      ),
      LyricProofreadAction.lineStructure => (
        LyricStructureStrings.actionTitle,
        LyricStructureStrings.actionDetail,
      ),
      LyricProofreadAction.timelineRepair => (
        LyricTimelineRepairStrings.actionTitle,
        LyricTimelineRepairStrings.actionDetail,
      ),
      LyricProofreadAction.timingShift => (
        LyricTimingShiftStrings.actionTitle,
        LyricTimingShiftStrings.actionDetail,
      ),
      LyricProofreadAction.paceCheck => (
        LyricPaceCheckStrings.actionTitle,
        LyricPaceCheckStrings.actionDetail,
      ),
      LyricProofreadAction.tapSync => (
        LyricTapSyncStrings.actionTitle,
        LyricTapSyncStrings.actionDetail,
      ),
      LyricProofreadAction.unifyChineseScript => (
        '统一简繁字形',
        '不需要参考歌词；先预览改动行数，默认跳过手动编辑过的行',
      ),
      LyricProofreadAction.findReplace => (
        LyricFindReplaceStrings.actionTitle,
        LyricFindReplaceStrings.actionDetail,
      ),
      LyricProofreadAction.viewComparison => ('查看逐行对比', '查看最近一次对齐的逐行差异'),
      LyricProofreadAction.undoAlignment => ('撤销最近更改', '未保存前有效'),
      LyricProofreadAction.restoreBackup => ('恢复对齐前版本', '需要使用前二次确认'),
    };
  }

  static IconData _iconFor(LyricProofreadAction action) {
    return switch (action) {
      LyricProofreadAction.proofreadV2 => Icons.auto_awesome_rounded,
      LyricProofreadAction.referenceAlignment => Icons.auto_fix_high_rounded,
      LyricProofreadAction.referenceProofread => Icons.spellcheck_rounded,
      LyricProofreadAction.repetitionConsistency =>
        Icons.library_add_check_rounded,
      LyricProofreadAction.textCleanup => Icons.cleaning_services_rounded,
      LyricProofreadAction.lineStructure => Icons.view_agenda_outlined,
      LyricProofreadAction.timelineRepair => Icons.healing_rounded,
      LyricProofreadAction.timingShift => Icons.timer_outlined,
      LyricProofreadAction.paceCheck => Icons.speed_rounded,
      LyricProofreadAction.tapSync => Icons.touch_app_rounded,
      LyricProofreadAction.unifyChineseScript => Icons.translate_rounded,
      LyricProofreadAction.findReplace => Icons.find_replace_rounded,
      LyricProofreadAction.viewComparison => Icons.compare_arrows_rounded,
      LyricProofreadAction.undoAlignment => Icons.undo_rounded,
      LyricProofreadAction.restoreBackup => Icons.history_rounded,
    };
  }
}

class _ProofreadMenuItem {
  const _ProofreadMenuItem({
    required this.title,
    required this.detail,
    required this.icon,
    required this.onPressed,
    required this.startsNewGroup,
  });

  final String title;
  final String? detail;
  final IconData icon;
  final VoidCallback onPressed;
  final bool startsNewGroup;
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.title, required this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              detail!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}
