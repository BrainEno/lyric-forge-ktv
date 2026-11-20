import 'package:flutter/material.dart';

import '../../../../core/theme/app_appearance.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Words of the 外观 card (decision D-042).
abstract final class AppearanceSettingsText {
  static const String group = '外观';
  static const String title = '主题';
  static const String subtitle = '界面的配色；选择会被记住，下次打开时保持不变。';
  static const String saveFailed = '未能保存主题选择，本次仍会使用，下次打开可能恢复为深色。';
}

/// The theme choice of 设置 › 外观: one preview tile per theme, painted with
/// that theme's own palette so each tile shows what picking it will look
/// like, whichever theme is in use.
class AppearanceSettingsCard extends StatelessWidget {
  const AppearanceSettingsCard({super.key, required this.controller});

  final AppAppearanceController controller;

  /// Key of the tile for [variant].
  static Key tileKey(AppThemeVariant variant) =>
      ValueKey('appearance-theme:${variant.id}');

  /// Below this width the tiles stack instead of sitting side by side.
  static const double stackBelowWidth = 340;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.variant;
        final failed = controller.saveError != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final tiles = [
                  for (final variant in AppThemeVariant.values)
                    AppearanceThemeTile(
                      key: tileKey(variant),
                      variant: variant,
                      selected: variant == current,
                      onSelect: () => controller.select(variant),
                    ),
                ];
                if (constraints.maxWidth < stackBelowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        tiles[i],
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                );
              },
            ),
            if (failed) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppearanceSettingsText.saveFailed,
                key: const ValueKey('appearance-save-failed'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.errorText),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One theme to pick: a miniature of the app in that theme, its name and
/// what it suits, and a check while it is the theme in use.
class AppearanceThemeTile extends StatelessWidget {
  const AppearanceThemeTile({
    super.key,
    required this.variant,
    required this.selected,
    required this.onSelect,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onSelect;

  /// Height of the miniature.
  static const double previewHeight = 72;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppSpacing.radiusLarge);
    return Semantics(
      button: true,
      selected: selected,
      label: '${variant.label}主题',
      hint: variant.description,
      onTap: onSelect,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.accentMuted : AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: previewHeight,
                  child: AppThemePreview(palette: variant.palette),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      variant.icon,
                      size: 18,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        variant.label,
                        style: text.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('appearance-theme-check'),
                        size: 20,
                        color: AppColors.accent,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  variant.description,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A miniature of the app painted with [palette], not with the palette in
/// use: a rail, a card with a title and a line of text, the accent's
/// selection pill and the brass "now playing" mark.
class AppThemePreview extends StatelessWidget {
  const AppThemePreview({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final small = BorderRadius.circular(AppSpacing.radiusSmall);
    Widget bar(Color color, double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: small),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.bgBase,
          border: Border.all(color: palette.borderSubtle),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The rail, with the selected destination's pill.
            Container(
              width: 20,
              color: palette.bgElevated,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                children: [
                  bar(palette.accentContainer, 12, 8),
                  const SizedBox(height: AppSpacing.xs),
                  bar(palette.textTertiary, 8, 4),
                  const SizedBox(height: AppSpacing.xs),
                  bar(palette.textTertiary, 8, 4),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: palette.bgElevated,
                    borderRadius: small,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(palette.textPrimary, 44, 6),
                      const SizedBox(height: AppSpacing.xs),
                      bar(palette.textSecondary, 64, 4),
                      const Spacer(),
                      Row(
                        children: [
                          bar(palette.accent, 28, 8),
                          const Spacer(),
                          bar(palette.vinylBrass, 8, 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
