import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/app_responsive.dart';
import '../theme/app_appearance_host.dart';
import '../theme/color_tokens.dart';
import '../widgets/app_tap_pulse.dart';
import '../widgets/app_theme_menu_button.dart';
import 'app_destinations.dart';
import 'mobile_destinations.dart';

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

/// Press counters of the four destinations, shared by the rail and the bottom
/// bar.
///
/// Both used to answer a press with nothing but the ink ripple, and pressing
/// the destination already open pushed its page again, so it looked like the
/// press had been ignored. Each press now bumps the destination's counter,
/// which pulses its icon (see [AppTapPulse]), and gives a selection click.
mixin _DestinationPresses<T extends StatefulWidget, D extends Object>
    on State<T> {
  final Map<D, int> _presses = {};

  int pressesOf(D destination) => _presses[destination] ?? 0;

  void press(D destination, ValueChanged<D> onSelect) {
    HapticFeedback.selectionClick();
    setState(() => _presses[destination] = pressesOf(destination) + 1);
    onSelect(destination);
  }

  /// The icon of [destination]. The selected and unselected icons are built
  /// the same way so the bar swaps the icon inside one pulse instead of
  /// starting a fresh one, which would cut the pulse short when the
  /// selection moves.
  Widget pulsingIcon(D destination, IconData icon) {
    return AppTapPulse(trigger: pressesOf(destination), child: Icon(icon));
  }
}

/// Vertical navigation for wide windows.
class AppNavigationRail extends StatefulWidget {
  final AppDestination? selected;
  final ValueChanged<AppDestination> onSelect;

  const AppNavigationRail({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  static const double collapsedWidth = 88;
  static const double extendedWidth = 200;

  /// Space above the first destination.
  static const double topInset = 12;

  @override
  State<AppNavigationRail> createState() => _AppNavigationRailState();
}

class _AppNavigationRailState extends State<AppNavigationRail>
    with _DestinationPresses<AppNavigationRail, AppDestination> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // Width comes from the window, not from the parent: the rail is installed
    // as a Row child, where constraints are unbounded and every child would
    // otherwise claim to be infinitely wide.
    final extended = MediaQuery.sizeOf(context).width >= 1200;
    // The theme button sits at the foot of the rail, away from the four
    // places (decision D-042). Absent when the app has no appearance
    // controller, as in most widget tests.
    final appearance = AppAppearanceScope.maybeOf(context);
    return SizedBox(
      width: extended
          ? AppNavigationRail.extendedWidth
          : AppNavigationRail.collapsedWidth,
      child: Material(
        color: AppColors.bgElevated,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              Expanded(child: _rail(selected, extended)),
              if (appearance != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppThemeMenuButton(
                    controller: appearance,
                    extended: extended,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(AppDestination? selected, bool extended) {
    return NavigationRail(
      backgroundColor: Colors.transparent,
      selectedIndex: selected == null
          ? null
          : AppDestination.values.indexOf(selected),
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      extended: extended,
      minExtendedWidth: AppNavigationRail.extendedWidth,
      minWidth: AppNavigationRail.collapsedWidth,
      groupAlignment: -0.9,
      onDestinationSelected: (index) =>
          press(AppDestination.values[index], widget.onSelect),
      // No brand mark above the destinations any more (D-049): the user
      // found the embedded mark distracting. A little air keeps the first
      // destination off the window's top edge.
      leading: const SizedBox(height: AppNavigationRail.topInset),
      destinations: [
        for (final destination in AppDestination.values)
          NavigationRailDestination(
            icon: Tooltip(
              message: destination.description,
              child: pulsingIcon(destination, destination.icon),
            ),
            selectedIcon: Tooltip(
              message: destination.description,
              child: pulsingIcon(destination, destination.selectedIcon),
            ),
            label: Text(destination.label),
          ),
      ],
    );
  }
}

/// Horizontal navigation for narrow windows.
class AppBottomNavigation extends StatefulWidget {
  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  const AppBottomNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation>
    with _DestinationPresses<AppBottomNavigation, AppDestination> {
  @override
  Widget build(BuildContext context) {
    // Colours, indicator and label weights come from the navigation bar
    // theme (lib/core/theme/app_theme.dart).
    return NavigationBar(
      backgroundColor: AppColors.bgElevated,
      selectedIndex: AppDestination.values.indexOf(widget.selected),
      onDestinationSelected: (index) =>
          press(AppDestination.values[index], widget.onSelect),
      destinations: [
        for (final destination in AppDestination.values)
          NavigationDestination(
            icon: pulsingIcon(destination, destination.icon),
            selectedIcon: pulsingIcon(destination, destination.selectedIcon),
            label: destination.label,
            tooltip: destination.description,
          ),
      ],
    );
  }
}

/// The phone's bottom bar: 听歌, 音乐库, 歌词 and 设置 (decision D-041).
///
/// Built like [AppBottomNavigation] — same theme, same press pulse and
/// click — over the phone's own destinations.
class AppMobileBottomNavigation extends StatefulWidget {
  final MobileDestination selected;
  final ValueChanged<MobileDestination> onSelect;

  const AppMobileBottomNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  /// The bar's height above the home indicator (D-058). Material's 80 left
  /// the phone's tab bar towering over the page; 64 still fits the 32-high
  /// pill and its label with room around them.
  static const double barHeight = 64;

  @override
  State<AppMobileBottomNavigation> createState() =>
      _AppMobileBottomNavigationState();
}

class _AppMobileBottomNavigationState extends State<AppMobileBottomNavigation>
    with _DestinationPresses<AppMobileBottomNavigation, MobileDestination> {
  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: AppColors.bgElevated,
      height: AppMobileBottomNavigation.barHeight,
      selectedIndex: MobileDestination.values.indexOf(widget.selected),
      onDestinationSelected: (index) =>
          press(MobileDestination.values[index], widget.onSelect),
      destinations: [
        for (final destination in MobileDestination.values)
          NavigationDestination(
            icon: pulsingIcon(destination, destination.icon),
            selectedIcon: pulsingIcon(destination, destination.selectedIcon),
            label: destination.label,
            tooltip: destination.description,
          ),
      ],
    );
  }
}
