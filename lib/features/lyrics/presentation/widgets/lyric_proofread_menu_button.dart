import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import 'auto_proofread_dialogs.dart';
import 'lyric_asr_loop_dialog.dart';
import 'lyric_batch_text_edit.dart';
import 'lyric_editor_actions.dart';
import 'lyric_find_replace_dialog.dart';
import 'lyric_missed_repeat_dialog.dart';
import 'lyric_pace_check_dialog.dart';
import 'lyric_repetition_consistency_dialog.dart';
import 'lyric_span_recognition_dialog.dart';
import 'lyric_structure_dialog.dart';
import 'lyric_tap_sync_dialog.dart';
import 'lyric_text_cleanup_dialog.dart';
import 'lyric_timeline_repair_dialog.dart';
import 'lyric_timing_shift_dialog.dart';
import 'lyric_vocal_gap_dialog.dart';
import 'lyric_word_tap_dialog.dart';
import 'lyric_word_timing_check_dialog.dart';
import 'reference_alignment_dialog.dart';

/// The proofreading capabilities.
///
/// The menu shows them in [LyricProofreadGroup] order and, within a group,
/// in declaration order. Generation actions come first because they are what
/// the user came for; reviewing and rolling back the last result is the last
/// group, so the destructive-sounding entries are not the first thing under
/// the cursor. The single-purpose checks that 一键校对 already runs (and the
/// expert checks) sit in one collapsed submenu (D-053).
enum LyricProofreadAction {
  autoProofread(LyricProofreadGroup.correction),
  smartProofread(LyricProofreadGroup.correction),
  referenceAlignment(LyricProofreadGroup.correction),
  spanRecognition(LyricProofreadGroup.correction),
  vocalGapRecognition(LyricProofreadGroup.correction),
  restoreRemovedLines(LyricProofreadGroup.correction),
  findReplace(LyricProofreadGroup.text),
  lineStructure(LyricProofreadGroup.text),
  tapSync(LyricProofreadGroup.timing),
  wordTap(LyricProofreadGroup.timing),
  timingShift(LyricProofreadGroup.timing),
  textCleanup(LyricProofreadGroup.checks),
  asrLoopCheck(LyricProofreadGroup.checks),
  repetitionConsistency(LyricProofreadGroup.checks),
  timelineRepair(LyricProofreadGroup.checks),
  missedRepeatCheck(LyricProofreadGroup.checks),
  paceCheck(LyricProofreadGroup.checks),
  wordTimingCheck(LyricProofreadGroup.checks),
  viewComparison(LyricProofreadGroup.review),
  undoAlignment(LyricProofreadGroup.review),
  restoreBackup(LyricProofreadGroup.review);

  const LyricProofreadAction(this.group);

  /// The menu section this action is listed under.
  final LyricProofreadGroup group;
}

/// The labelled sections of the proofreading menu, in display order.
enum LyricProofreadGroup {
  /// 一键校对, the other whole-song corrections and re-recognition.
  correction('智能纠错'),

  /// Edits the user directs: replacing a word, re-breaking rows.
  text('文本整理'),

  /// Tap-to-sync and moving timing by hand.
  timing('时间轴与打轴'),

  /// Single-purpose checks, collapsed into one submenu: the first four are
  /// steps of 一键校对, the rest are for detailed work.
  checks(
    '单项检查',
    detail: '一键校对已包含清理、循环、重复段落和时间轴检查；这里可逐项查看',
    collapsed: true,
  ),

  /// Looking at and rolling back the last alignment.
  review('对比与回滚');

  const LyricProofreadGroup(this.label, {this.detail, this.collapsed = false});

  final String label;

  /// Subtitle of a [collapsed] group's submenu entry.
  final String? detail;

  /// Shown as one submenu entry instead of a labelled section.
  final bool collapsed;
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
    this.onAutoProofread,
    this.onSmartProofread,
    this.onReferenceAlignment,
    this.onRepetitionConsistency,
    this.onTextCleanup,
    this.onAsrLoopCheck,
    this.onMissedRepeatCheck,
    this.onSpanRecognition,
    this.onVocalGapRecognition,
    this.onRestoreRemovedLines,
    this.onLineStructure,
    this.onTimelineRepair,
    this.onTimingShift,
    this.onPaceCheck,
    this.onTapSync,
    this.onWordTap,
    this.onWordTimingCheck,
    this.onFindReplace,
    this.onViewComparison,
    this.onUndoAlignment,
    this.onRestoreBackup,
    this.compact = false,
  });

  /// The menu for the editor's [actions] group.
  ///
  /// The toolbar and the narrow app bar used to spell out the same twenty
  /// arguments each, mapping every batch tool to its callback by hand, so a
  /// new tool had to be wired in three places (audit E-04). The mapping now
  /// lives here once.
  factory LyricProofreadMenuButton.forActions(
    LyricProofreadActions actions, {
    Key? key,
    bool compact = false,
  }) {
    final open = actions.onBatchTextTool;
    VoidCallback? tool(LyricBatchTextTool value) =>
        open == null ? null : () => open(value);
    return LyricProofreadMenuButton(
      key: key,
      compact: compact,
      onAutoProofread: actions.onAutoProofread,
      onSmartProofread: actions.onSmartProofread,
      onReferenceAlignment: actions.onReferenceAlignment,
      onRepetitionConsistency: tool(LyricBatchTextTool.repetitionConsistency),
      onTextCleanup: tool(LyricBatchTextTool.textCleanup),
      onAsrLoopCheck: tool(LyricBatchTextTool.asrLoopCheck),
      onMissedRepeatCheck: tool(LyricBatchTextTool.missedRepeatCheck),
      onSpanRecognition: tool(LyricBatchTextTool.spanRecognition),
      onVocalGapRecognition: tool(LyricBatchTextTool.vocalGapRecognition),
      onRestoreRemovedLines: tool(LyricBatchTextTool.restoreRemovedLines),
      onLineStructure: tool(LyricBatchTextTool.lineStructure),
      onTimelineRepair: tool(LyricBatchTextTool.timelineRepair),
      onTimingShift: tool(LyricBatchTextTool.timingShift),
      onPaceCheck: tool(LyricBatchTextTool.paceCheck),
      onTapSync: tool(LyricBatchTextTool.tapSync),
      onWordTap: tool(LyricBatchTextTool.wordTap),
      onWordTimingCheck: tool(LyricBatchTextTool.wordTimingCheck),
      onFindReplace: tool(LyricBatchTextTool.findReplace),
      onViewComparison: actions.onViewAlignmentComparison,
      onUndoAlignment: actions.onUndoReferenceAlignment,
      onRestoreBackup: actions.onRestoreAlignment,
    );
  }

  /// 一键校对: finds the lyric online and applies every safe correction.
  final VoidCallback? onAutoProofread;

  /// 智能校对: builds a proposal from the ASR evidence without writing it.
  final VoidCallback? onSmartProofread;

  /// 粘贴参考歌词校对 — aligns a pasted reference and can replace timing.
  final VoidCallback? onReferenceAlignment;

  /// 重复段落一致性检查: unifies repeats (choruses) recognised differently.
  final VoidCallback? onRepetitionConsistency;

  /// 清理识别文本: strips punctuation, annotations and caption boilerplate.
  final VoidCallback? onTextCleanup;

  /// 识别循环检查: cuts down phrases and rows the recogniser repeated.
  final VoidCallback? onAsrLoopCheck;

  /// 漏唱和声检查: finds chants and backing vocals the recogniser shortened.
  final VoidCallback? onMissedRepeatCheck;

  /// 重新识别这一段: re-runs a stretch of rows through a recogniser.
  final VoidCallback? onSpanRecognition;

  /// 识别有人声没歌词的段落: recognises singing the vocal check found
  /// without lyrics.
  final VoidCallback? onVocalGapRecognition;

  /// 恢复人声检查删除的行: puts rows the vocal check removed back.
  final VoidCallback? onRestoreRemovedLines;

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

  /// Opens word-by-word tap-to-sync (逐字打轴).
  final VoidCallback? onWordTap;

  /// Opens the word timing check (逐字时间检查).
  final VoidCallback? onWordTimingCheck;

  /// 批量查找替换: replaces a misrecognised word everywhere at once.
  final VoidCallback? onFindReplace;

  final VoidCallback? onViewComparison;
  final VoidCallback? onUndoAlignment;
  final VoidCallback? onRestoreBackup;

  /// Icon-only variant for the app bar on narrow layouts.
  final bool compact;

  static const String label = '校对';

  /// Menu title of the no-reference proposal flow ([onSmartProofread]).
  static const String smartProofreadTitle = '智能校对';

  /// Its menu subtitle: when to use it, in plain words.
  static const String smartProofreadDetail = '没有歌词原文时用；按识别结果给出逐行修改建议，确认后才应用';

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    if (groups.isEmpty) return const SizedBox.shrink();

    return MenuAnchor(
      menuChildren: [
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const Divider(height: 1),
          if (group.$1.collapsed)
            SubmenuButton(
              leadingIcon: const Icon(Icons.checklist_rounded, size: 18),
              menuChildren: [for (final item in group.$2) _menuItem(item)],
              child: _MenuLabel(title: group.$1.label, detail: group.$1.detail),
            )
          else ...[
            _GroupHeader(group.$1.label),
            for (final item in group.$2) _menuItem(item),
          ],
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
          message: '校对：一键校对、重新识别、文本与时间轴整理、单项检查',
          child: FilledButton.tonalIcon(
            onPressed: open,
            icon: const Icon(Icons.spellcheck_rounded, size: 18),
            label: const Text(label),
          ),
        );
      },
    );
  }

  static Widget _menuItem(_ProofreadMenuItem item) => MenuItemButton(
    onPressed: item.onPressed,
    leadingIcon: Icon(item.icon, size: 18),
    child: _MenuLabel(title: item.title, detail: item.detail),
  );

  /// Available entries per group; groups without any entry are left out.
  List<(LyricProofreadGroup, List<_ProofreadMenuItem>)> _groups() {
    final actions = <LyricProofreadAction, VoidCallback?>{
      LyricProofreadAction.autoProofread: onAutoProofread,
      LyricProofreadAction.smartProofread: onSmartProofread,
      LyricProofreadAction.referenceAlignment: onReferenceAlignment,
      LyricProofreadAction.repetitionConsistency: onRepetitionConsistency,
      LyricProofreadAction.textCleanup: onTextCleanup,
      LyricProofreadAction.asrLoopCheck: onAsrLoopCheck,
      LyricProofreadAction.missedRepeatCheck: onMissedRepeatCheck,
      LyricProofreadAction.spanRecognition: onSpanRecognition,
      LyricProofreadAction.vocalGapRecognition: onVocalGapRecognition,
      LyricProofreadAction.restoreRemovedLines: onRestoreRemovedLines,
      LyricProofreadAction.lineStructure: onLineStructure,
      LyricProofreadAction.timelineRepair: onTimelineRepair,
      LyricProofreadAction.timingShift: onTimingShift,
      LyricProofreadAction.paceCheck: onPaceCheck,
      LyricProofreadAction.tapSync: onTapSync,
      LyricProofreadAction.wordTap: onWordTap,
      LyricProofreadAction.wordTimingCheck: onWordTimingCheck,
      LyricProofreadAction.findReplace: onFindReplace,
      LyricProofreadAction.viewComparison: onViewComparison,
      LyricProofreadAction.undoAlignment: onUndoAlignment,
      LyricProofreadAction.restoreBackup: onRestoreBackup,
    };

    final groups = <(LyricProofreadGroup, List<_ProofreadMenuItem>)>[];
    for (final group in LyricProofreadGroup.values) {
      final items = <_ProofreadMenuItem>[];
      for (final action in LyricProofreadAction.values) {
        final callback = actions[action];
        if (callback == null || action.group != group) continue;
        final text = _textFor(action);
        items.add(
          _ProofreadMenuItem(
            title: text.$1,
            detail: text.$2,
            icon: _iconFor(action),
            onPressed: callback,
          ),
        );
      }
      if (items.isNotEmpty) groups.add((group, items));
    }
    return groups;
  }

  /// Title plus the one-line explanation that distinguishes the strategies.
  static (String, String?) _textFor(LyricProofreadAction action) {
    return switch (action) {
      LyricProofreadAction.autoProofread => (
        AutoProofreadStrings.actionTitle,
        AutoProofreadStrings.actionDetail,
      ),
      LyricProofreadAction.smartProofread => (
        smartProofreadTitle,
        smartProofreadDetail,
      ),
      LyricProofreadAction.referenceAlignment => (
        ReferenceLyricPurpose.alignment.title,
        ReferenceLyricPurpose.alignment.menuDetail,
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
      LyricProofreadAction.asrLoopCheck => (
        LyricAsrLoopStrings.actionTitle,
        LyricAsrLoopStrings.actionDetail,
      ),
      LyricProofreadAction.missedRepeatCheck => (
        LyricMissedRepeatStrings.actionTitle,
        LyricMissedRepeatStrings.actionDetail,
      ),
      LyricProofreadAction.spanRecognition => (
        LyricSpanRecognitionStrings.actionTitle,
        LyricSpanRecognitionStrings.actionDetail,
      ),
      LyricProofreadAction.vocalGapRecognition => (
        LyricVocalCheckStrings.gapTitle,
        LyricVocalCheckStrings.gapDetail,
      ),
      LyricProofreadAction.restoreRemovedLines => (
        LyricVocalCheckStrings.restoreTitle,
        LyricVocalCheckStrings.restoreDetail,
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
      LyricProofreadAction.wordTap => (
        LyricWordTapStrings.actionTitle,
        LyricWordTapStrings.actionDetail,
      ),
      LyricProofreadAction.wordTimingCheck => (
        LyricWordTimingCheckStrings.actionTitle,
        LyricWordTimingCheckStrings.actionDetail,
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
      LyricProofreadAction.autoProofread => Icons.bolt_rounded,
      LyricProofreadAction.smartProofread => Icons.auto_awesome_rounded,
      LyricProofreadAction.referenceAlignment => Icons.auto_fix_high_rounded,
      LyricProofreadAction.repetitionConsistency =>
        Icons.library_add_check_rounded,
      LyricProofreadAction.textCleanup => Icons.cleaning_services_rounded,
      LyricProofreadAction.asrLoopCheck => Icons.repeat_one_rounded,
      LyricProofreadAction.missedRepeatCheck => Icons.playlist_add_rounded,
      LyricProofreadAction.spanRecognition =>
        Icons.published_with_changes_rounded,
      LyricProofreadAction.vocalGapRecognition =>
        Icons.record_voice_over_rounded,
      LyricProofreadAction.restoreRemovedLines =>
        Icons.settings_backup_restore_rounded,
      LyricProofreadAction.lineStructure => Icons.view_agenda_outlined,
      LyricProofreadAction.timelineRepair => Icons.healing_rounded,
      LyricProofreadAction.timingShift => Icons.timer_outlined,
      LyricProofreadAction.paceCheck => Icons.speed_rounded,
      LyricProofreadAction.tapSync => Icons.touch_app_rounded,
      LyricProofreadAction.wordTap => Icons.lyrics_outlined,
      LyricProofreadAction.wordTimingCheck => Icons.fact_check_outlined,
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
  });

  final String title;
  final String? detail;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Non-interactive section title inside the menu.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
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
