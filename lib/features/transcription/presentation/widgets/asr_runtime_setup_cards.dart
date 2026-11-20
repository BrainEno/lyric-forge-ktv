import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import 'asr_runtime_setup_controller.dart';
import 'asr_runtime_setup_text.dart';

// The stateless pieces of the first-run setup dialog (audit I-03): the
// header, the numbered steps, the profile and component cards, the hint and
// the buttons. They used to be private classes at the end of the 957-line
// dialog; the dialog now only arranges them.

/// The coloured top of the dialog: what state the setup is in.
class AsrSetupHeader extends StatelessWidget {
  const AsrSetupHeader({
    super.key,
    required this.ready,
    required this.installing,
  });

  final bool ready;
  final bool installing;

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppColors.success : AppColors.accent;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXLarge),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: Icon(
              ready ? Icons.check_rounded : Icons.graphic_eq_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    AsrSetupText.headerTitle(
                      ready: ready,
                      installing: installing,
                    ),
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AsrSetupText.headerSubtitle(ready: ready),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered step heading: `1 选择识别方案` with a line below.
class AsrSetupStep extends StatelessWidget {
  const AsrSetupStep({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        header: true,
        label: '第 $number 步',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(
                    AppSpacing.radiusCircular,
                  ),
                ),
                child: Text(
                  '$number',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quality mode menu of step 1.
class AsrSetupModeField extends StatelessWidget {
  const AsrSetupModeField({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final TranscriptionMode mode;

  /// Null while downloading, which greys the menu out.
  final ValueChanged<TranscriptionMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    // Expanded, so a narrow window shortens the option with an ellipsis
    // instead of overflowing the field.
    return DropdownButtonFormField<TranscriptionMode>(
      initialValue: mode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: AsrSetupText.modeLabel),
      items: [
        for (final option in AsrSetupText.modes)
          DropdownMenuItem(
            value: option,
            child: Text(
              AsrSetupText.modeOption(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: changed == null
          ? null
          : (value) {
              if (value != null) changed(value);
            },
    );
  }
}

/// The hardware profile the plan was matched to.
class AsrSetupProfileCard extends StatelessWidget {
  const AsrSetupProfileCard({
    super.key,
    required this.title,
    required this.description,
    required this.hardware,
    required this.ready,
  });

  /// The card for the profile in [status].
  factory AsrSetupProfileCard.fromStatus(AsrRuntimeStatus status, {Key? key}) {
    return AsrSetupProfileCard(
      key: key,
      title: status.profile.label,
      description: status.profile.description,
      hardware: AsrSetupText.hardwareSummary(status.profile.hardware),
      ready: status.isReady,
    );
  }

  final String title;
  final String description;
  final String hardware;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final accent = ready ? AppColors.success : AppColors.info;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(
          color: ready
              ? AppColors.success.withAlpha(90)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withAlpha(22),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Icon(
              ready ? Icons.check_circle_outline_rounded : Icons.memory_rounded,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      AsrSetupText.profileBadge(ready: ready),
                      style: textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hardware,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The components the plan needs, one row each with its state.
class AsrSetupComponentsCard extends StatelessWidget {
  const AsrSetupComponentsCard({
    super.key,
    required this.components,
    required this.ready,
  });

  final List<AsrRuntimeComponentStatus> components;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AsrSetupText.componentsTitle(ready: ready),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < components.length; index++) ...[
            AsrSetupComponentRow(component: components[index]),
            if (index != components.length - 1)
              const Divider(
                height: AppSpacing.md,
                color: AppColors.borderMuted,
              ),
          ],
        ],
      ),
    );
  }
}

/// One component: its name, a detail line and whether it is prepared.
///
/// A screen reader hears the row once, e.g. `FFmpeg，已准备，系统已安装`,
/// instead of the icon, name, detail and state as four stops.
class AsrSetupComponentRow extends StatelessWidget {
  const AsrSetupComponentRow({super.key, required this.component});

  final AsrRuntimeComponentStatus component;

  /// The icon and colour of [state].
  static (IconData, Color) styleFor(AsrRuntimeComponentState state) {
    return switch (state) {
      AsrRuntimeComponentState.ready => (
        Icons.check_circle_rounded,
        AppColors.success,
      ),
      AsrRuntimeComponentState.unavailable => (
        Icons.tune_rounded,
        AppColors.warning,
      ),
      AsrRuntimeComponentState.missing ||
      AsrRuntimeComponentState.installing ||
      AsrRuntimeComponentState.failed => (
        Icons.radio_button_unchecked_rounded,
        AppColors.textTertiary,
      ),
    };
  }

  /// The row as one sentence.
  static String semanticLabel(AsrRuntimeComponentStatus component) {
    return [
      component.label.trim(),
      AsrSetupText.componentState(component.state),
      component.detail.trim(),
    ].where((part) => part.isNotEmpty).join('，');
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = styleFor(component.state);
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticLabel(component),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(component.label, style: textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  component.detail,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AsrSetupText.componentState(component.state),
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The reassurance at the end of the dialog.
class AsrSetupHint extends StatelessWidget {
  const AsrSetupHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AsrSetupText.hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One button of the dialog's action row.
///
/// The last button is the filled one: 继续下载 when paused, 校验并准备 or
/// 开始使用 otherwise. While space is short the install button says 空间不足
/// and is disabled, so the reason is on the button itself.
class AsrSetupActionButton extends StatelessWidget {
  const AsrSetupActionButton({
    super.key,
    required this.action,
    required this.onPressed,
    this.storageBlocked = false,
  });

  final AsrSetupAction action;

  /// Null greys the button out.
  final VoidCallback? onPressed;
  final bool storageBlocked;

  /// Whether [action] is the dialog's main, filled button.
  static bool isPrimary(AsrSetupAction action) => switch (action) {
    AsrSetupAction.resume ||
    AsrSetupAction.install ||
    AsrSetupAction.start => true,
    AsrSetupAction.pause ||
    AsrSetupAction.later ||
    AsrSetupAction.advanced ||
    AsrSetupAction.refresh => false,
  };

  @override
  Widget build(BuildContext context) {
    return switch (action) {
      AsrSetupAction.pause => TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.pause_rounded, size: 18),
        label: const Text('暂停下载'),
      ),
      AsrSetupAction.later => TextButton(
        onPressed: onPressed,
        child: const Text('以后继续'),
      ),
      AsrSetupAction.resume => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('继续下载'),
      ),
      AsrSetupAction.advanced => TextButton(
        onPressed: onPressed,
        child: const Text('高级设置'),
      ),
      AsrSetupAction.refresh => TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('重新检测'),
      ),
      AsrSetupAction.install => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(AsrSetupText.installLabel(storageBlocked: storageBlocked)),
      ),
      AsrSetupAction.start => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('开始使用'),
      ),
    };
  }
}
