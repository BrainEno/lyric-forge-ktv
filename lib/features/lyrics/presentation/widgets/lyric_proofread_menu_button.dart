import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';

/// The proofreading capabilities, in the order they are offered.
///
/// Generation actions come first because they are what the user came for;
/// reviewing and rolling back the last result sits behind a divider so the
/// destructive-sounding entries are not the first thing under the cursor.
enum LyricProofreadAction {
  proofreadV2,
  referenceAlignment,
  referenceProofread,
  viewComparison,
  undoAlignment,
  restoreBackup,
}

/// One entry point for every proofreading flow.
///
/// The editor used to expose four to six separate buttons for this, each with a
/// label the user had to decode before understanding the difference. The flows
/// themselves are unchanged; only the入口 is now a single menu, so the two
/// distinct strategies (with and without reference lyrics) are described next to
/// each other instead of hidden in different corners of the toolbar.
class LyricProofreadMenuButton extends StatelessWidget {
  const LyricProofreadMenuButton({
    super.key,
    this.onProofreadV2,
    this.onReferenceAlignment,
    this.onReferenceProofread,
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
          message: '校对：智能提案、参考歌词纠正、逐行对比与回滚',
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
