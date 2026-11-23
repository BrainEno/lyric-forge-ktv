import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_command_keys.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/keyboard_shortcut_catalog.dart';

bool _panelOpen = false;

/// Shows every keyboard shortcut (D-065). Does nothing while the panel is
/// already open, so pressing ? twice does not stack two.
Future<void> showKeyboardShortcuts(BuildContext context) async {
  if (_panelOpen) return;
  _panelOpen = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => const KeyboardShortcutsPanel(),
    );
  } finally {
    _panelOpen = false;
  }
}

/// The shortcut panel: one card per place in the app, two columns on wide
/// windows.
class KeyboardShortcutsPanel extends StatelessWidget {
  const KeyboardShortcutsPanel({super.key});

  static const panelKey = ValueKey('keyboard-shortcuts-panel');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = theme.platform;
    final groups = keyboardShortcutGroups(
      apple: AppCommandKeys.isApple(platform),
    );
    final compact = AppResponsive.of(context).isCompact;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard_outlined, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '快捷键',
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final width = constraints.maxWidth - 2 * AppSpacing.lg;
        final column = width >= 640 ? (width - gap) / 2 : width;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final group in groups)
                SizedBox(
                  width: column,
                  child: _GroupCard(group: group, platform: platform),
                ),
            ],
          ),
        );
      },
    );
    final content = Column(
      key: panelKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const Divider(height: 1),
        Flexible(child: body),
      ],
    );
    if (compact) {
      return Dialog.fullscreen(
        backgroundColor: AppColors.bgElevated,
        child: SafeArea(child: content),
      );
    }
    return Dialog(
      backgroundColor: AppColors.bgElevated,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: content,
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.platform});

  final KeyboardShortcutGroup group;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = group.note;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            for (final shortcut in group.shortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: _ShortcutRow(shortcut: shortcut, platform: platform),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcut, required this.platform});

  final KeyboardShortcut shortcut;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alternative = shortcut.alternative;
    final hint = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textTertiary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(shortcut.action, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          flex: 2,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              ..._caps(shortcut.keys, hint),
              if (alternative != null) ...[
                Text('或', style: hint),
                ..._caps(alternative, hint),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _caps(List<String> keys, TextStyle? hint) => [
    for (var i = 0; i < keys.length; i++) ...[
      if (i > 0) Text('+', style: hint),
      KeyCap(
        keys[i] == commandKey ? AppCommandKeys.modifier(platform) : keys[i],
      ),
    ],
  ];
}

/// One key drawn as a key cap.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        border: Border.all(color: AppColors.borderMuted),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 2,
          vertical: 2,
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
