import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import '../theme/color_tokens.dart';
import 'app_destinations.dart';

/// Persistent top-level navigation: a rail on wide windows, a bottom bar on
/// narrow ones.
///
/// It is installed around the whole `MaterialApp` navigator rather than inside
/// individual screens, because the problem it fixes is exactly the one
/// per-screen navigation cannot fix: no single screen knows which of the four
/// places the user came from, and every screen would have to be taught
/// separately.
///
/// The parts are exposed separately ([AppNavigationRail] and
/// [AppBottomNavigation]) because the shell has to slot around chrome the app
/// already owns — on desktop the rail spans the full window height beside the
/// player bar, and on mobile the player bar sits between the content and the
/// bottom navigation. Composing that from one widget would have put the mini
/// player underneath the tab bar.
class AppNavigationShell extends StatelessWidget {
  /// Current route, used only to highlight a destination.
  final String? currentRoute;

  /// Called when the user picks a destination. The caller owns routing, so the
  /// shell stays testable without a Navigator.
  final ValueChanged<AppDestination> onSelect;

  /// Hidden while the user is watching something full-screen.
  final bool hidden;

  final Widget child;

  const AppNavigationShell({
    super.key,
    required this.currentRoute,
    required this.onSelect,
    required this.child,
    this.hidden = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hidden) return child;
    final layout = AppResponsive.of(context);
    final selected = destinationForRoute(currentRoute);
    // No destination means this route is not part of the four places — device
    // transfer and the immersive player. Showing a navigation with nothing
    // highlighted would only ask the user where they are.
    if (selected == null) return child;

    if (layout.useNavigationRail) {
      return Row(
        children: [
          AppNavigationRail(selected: selected, onSelect: onSelect),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: child),
        AppBottomNavigation(selected: selected, onSelect: onSelect),
      ],
    );
  }
}

/// Vertical navigation for wide windows.
class AppNavigationRail extends StatelessWidget {
  final AppDestination? selected;
  final ValueChanged<AppDestination> onSelect;

  const AppNavigationRail({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  static const double collapsedWidth = 88;
  static const double extendedWidth = 200;

  @override
  Widget build(BuildContext context) {
    // Width comes from the window, not from the parent: the rail is installed
    // as a Row child, where constraints are unbounded and every child would
    // otherwise claim to be infinitely wide.
    final extended = MediaQuery.sizeOf(context).width >= 1200;
    return SizedBox(
      width: extended ? extendedWidth : collapsedWidth,
      child: Material(
        color: AppColors.bgElevated,
        child: SafeArea(
          right: false,
          child: NavigationRail(
            backgroundColor: Colors.transparent,
            selectedIndex: selected == null
                ? null
                : AppDestination.values.indexOf(selected!),
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            extended: extended,
            minExtendedWidth: extendedWidth,
            minWidth: collapsedWidth,
            groupAlignment: -0.9,
            onDestinationSelected: (index) =>
                onSelect(AppDestination.values[index]),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.graphic_eq_rounded, size: 28),
            ),
            destinations: [
              for (final destination in AppDestination.values)
                NavigationRailDestination(
                  icon: Tooltip(
                    message: destination.description,
                    child: Icon(destination.icon),
                  ),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal navigation for narrow windows.
class AppBottomNavigation extends StatelessWidget {
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  const AppBottomNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: AppColors.bgElevated,
      selectedIndex: AppDestination.values.indexOf(selected),
      onDestinationSelected: (index) => onSelect(AppDestination.values[index]),
      destinations: [
        for (final destination in AppDestination.values)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
            tooltip: destination.description,
          ),
      ],
    );
  }
}
