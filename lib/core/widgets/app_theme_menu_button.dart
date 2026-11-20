import 'package:flutter/material.dart';

import '../theme/app_appearance.dart';
import '../theme/app_palette.dart';
import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// The theme button at the foot of the desktop rail (decision D-042): it
/// shows the icon of the theme in use and opens the list of themes.
///
/// A [MenuAnchor] rather than a popup menu route: the rail is chrome beside
/// the navigator, not under it, so a menu that pushes a route would find no
/// navigator. The anchor opens in the chrome's own overlay.
class AppThemeMenuButton extends StatelessWidget {
  const AppThemeMenuButton({
    super.key,
    required this.controller,
    this.extended = false,
  });

  final AppAppearanceController controller;

  /// Show the theme's name beside the icon, for the wide rail.
  final bool extended;

  static const Key buttonKey = ValueKey('app-theme-menu-button');

  /// Key of the menu entry for [variant].
  static Key itemKey(AppThemeVariant variant) =>
      ValueKey('app-theme-menu-item:${variant.id}');

  /// What the button's tooltip and screen readers say.
  static String tooltipFor(AppThemeVariant variant) =>
      '外观：${variant.label}（点按切换主题）';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.variant;
        return MenuAnchor(
          alignmentOffset: const Offset(AppSpacing.sm, 0),
          menuChildren: [
            for (final variant in AppThemeVariant.values)
              MenuItemButton(
                key: itemKey(variant),
                leadingIcon: Icon(variant.icon),
                trailingIcon: variant == current
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onPressed: () => controller.select(variant),
                child: Semantics(
                  selected: variant == current,
                  child: Text('${variant.label}主题'),
                ),
              ),
          ],
          builder: (context, menu, _) {
            void toggle() => menu.isOpen ? menu.close() : menu.open();
            final icon = Icon(current.icon);
            if (extended) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Tooltip(
                  message: tooltipFor(current),
                  child: TextButton.icon(
                    key: buttonKey,
                    onPressed: toggle,
                    icon: icon,
                    label: Text('外观 · ${current.label}'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size.fromHeight(48),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                  ),
                ),
              );
            }
            return IconButton(
              key: buttonKey,
              tooltip: tooltipFor(current),
              onPressed: toggle,
              icon: icon,
            );
          },
        );
      },
    );
  }
}
