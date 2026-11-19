import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';

/// Responsive grid of [AsrInfoTile]s: one column on phones, two from 640 px
/// and three from 980 px of available width.
class AsrInfoGrid extends StatelessWidget {
  const AsrInfoGrid({super.key, required this.children});

  final List<Widget> children;

  /// Number of tile columns for [width].
  static int columnsFor(double width) {
    if (width >= 980) return 3;
    if (width >= 640) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = columnsFor(width);
        const gap = AppSpacing.sm;
        final tileWidth = columns == 1
            ? width
            : (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}

/// One fact about the recognition environment: a muted label, a bold value
/// and an optional explanation.
class AsrInfoTile extends StatelessWidget {
  const AsrInfoTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
    this.selectable = false,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;

  /// Lets the value be selected and copied (paths); selectable values are not
  /// truncated.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final explanation = detail;
    final valueWidget = Text(
      value,
      maxLines: selectable ? null : 3,
      overflow: selectable ? null : TextOverflow.ellipsis,
      style: text.bodyMedium?.copyWith(
        color: valueColor,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (selectable) SelectionArea(child: valueWidget) else valueWidget,
          if (explanation != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              explanation,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bordered list of runtime components with their install state.
class AsrComponentList extends StatelessWidget {
  const AsrComponentList({super.key, required this.components});

  final List<AsrRuntimeComponentStatus> components;

  /// Chinese label for a component state.
  static String stateLabel(AsrRuntimeComponentState state) {
    return switch (state) {
      AsrRuntimeComponentState.ready => '已安装',
      AsrRuntimeComponentState.missing => '未安装',
      AsrRuntimeComponentState.installing => '安装中',
      AsrRuntimeComponentState.failed => '安装失败',
      AsrRuntimeComponentState.unavailable => '不可用',
    };
  }

  /// Badge tone for a component state.
  static AppBadgeTone stateTone(AsrRuntimeComponentState state) {
    return switch (state) {
      AsrRuntimeComponentState.ready => AppBadgeTone.success,
      AsrRuntimeComponentState.installing => AppBadgeTone.info,
      AsrRuntimeComponentState.failed => AppBadgeTone.error,
      AsrRuntimeComponentState.missing => AppBadgeTone.neutral,
      AsrRuntimeComponentState.unavailable => AppBadgeTone.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        children: [
          for (var index = 0; index < components.length; index++) ...[
            _ComponentRow(component: components[index]),
            if (index != components.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({required this.component});

  final AsrRuntimeComponentStatus component;

  @override
  Widget build(BuildContext context) {
    final ready = component.state == AsrRuntimeComponentState.ready;
    return ListTile(
      dense: true,
      leading: Icon(
        ready
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: ready ? AppColors.success : AppColors.textTertiary,
      ),
      title: Text(component.label),
      subtitle: Text(component.detail),
      trailing: AppBadge(
        label: AsrComponentList.stateLabel(component.state),
        tone: AsrComponentList.stateTone(component.state),
        size: AppBadgeSize.small,
      ),
    );
  }
}
