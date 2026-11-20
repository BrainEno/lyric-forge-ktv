import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/layout/app_responsive.dart';
import '../core/navigation/app_chrome_controller.dart';
import '../core/navigation/app_chrome_scope.dart';
import '../core/navigation/app_destinations.dart';
import '../core/navigation/app_navigation_shell.dart';
import '../core/navigation/mobile_destinations.dart';
import '../core/navigation/routes.dart';

/// Everything the app draws around the navigator: the persistent navigation,
/// the player bar and, on desktop, the transcription queue bar.
///
/// Split out of `app.dart` for two bugs that a widget test can now pin down:
///
///  * The chrome lives in an [Overlay] so its tooltips and menus have
///    somewhere to go. On desktop it used to be built as
///    `Overlay(initialEntries: …)` straight from the route listener, but an
///    overlay reads its initial entries once: the entry kept the closure of
///    the first frame, so the rail went on highlighting 工程 and the player bar
///    stayed up on the full player whatever the user opened. The entry is now
///    created once and reads the route itself. The mobile chrome had no
///    overlay at all, so the bottom bar's destination tooltips (long press)
///    had nowhere to go and threw; it now shares the same host.
///  * The chrome sits beside the navigator, not under it, so it reaches the
///    navigator through [AppChromeScope].
class AppChrome extends StatelessWidget {
  const AppChrome({
    super.key,
    required this.desktop,
    required this.navigatorKey,
    required this.currentRoute,
    required this.onSelectDestination,
    required this.onSelectMobileDestination,
    required this.child,
    this.queueBar,
    this.playerBar,
  });

  /// Desktop chrome (rail, queue bar, overlay) instead of the mobile one.
  final bool desktop;

  final GlobalKey<NavigatorState> navigatorKey;

  /// Name of the visible route.
  final ValueListenable<String?> currentRoute;

  /// Called when a destination is pressed in the desktop rail.
  final ValueChanged<AppDestination> onSelectDestination;

  /// Called when a destination is pressed in the phone's bottom bar, whose
  /// destinations differ from the desktop's (decision D-041).
  final ValueChanged<MobileDestination> onSelectMobileDestination;

  /// The navigator.
  final Widget child;

  /// Desktop only: the background transcription progress strip.
  final Widget? queueBar;

  /// The mini player for this platform. Hidden on the full player, which has
  /// its own transport.
  final Widget? playerBar;

  @override
  Widget build(BuildContext context) {
    return AppChromeScope(
      navigatorKey: navigatorKey,
      currentRoute: currentRoute,
      child: _ChromeOverlay(chrome: this),
    );
  }
}

/// Holds the single overlay entry of the chrome.
class _ChromeOverlay extends StatefulWidget {
  const _ChromeOverlay({required this.chrome});

  final AppChrome chrome;

  @override
  State<_ChromeOverlay> createState() => _ChromeOverlayState();
}

class _ChromeOverlayState extends State<_ChromeOverlay> {
  // Owned by the overlay below for the life of the app shell, like the entry
  // it replaces; it is never removed on its own.
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) =>
        _ChromeLayout(chrome: widget.chrome, desktop: widget.chrome.desktop),
  );

  @override
  void didUpdateWidget(covariant _ChromeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The overlay never looks at its entries again, so a new navigator child
    // or player bar has to be pushed into the entry by hand.
    if (!identical(oldWidget.chrome, widget.chrome)) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(clipBehavior: Clip.none, initialEntries: [_entry]);
  }
}

/// Lays the chrome out for the current route and immersive state.
class _ChromeLayout extends StatelessWidget {
  const _ChromeLayout({required this.chrome, required this.desktop});

  final AppChrome chrome;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: chrome.currentRoute,
      builder: (context, routeName, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppChromeController.immersive,
          builder: (context, immersive, _) => desktop
              ? _desktop(context, routeName, immersive)
              : _mobile(context, routeName, immersive),
        );
      },
    );
  }

  Widget? _playerBarFor(String? routeName) =>
      routeName == Routes.nowPlaying ? null : chrome.playerBar;

  Widget _mobile(BuildContext context, String? routeName, bool immersive) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showChrome = !immersive && !keyboardVisible;
    final destination = mobileDestinationForRoute(routeName);
    // The listening home is the player itself — record, seek bar and
    // transport — so the mini player would only repeat it (D-041).
    final playerBar = destination == MobileDestination.listen
        ? null
        : _playerBarFor(routeName);
    return Column(
      children: [
        Expanded(child: chrome.child),
        if (showChrome && playerBar != null) playerBar,
        if (showChrome && destination != null)
          AppMobileBottomNavigation(
            key: const ValueKey('app-bottom-navigation'),
            selected: destination,
            onSelect: chrome.onSelectMobileDestination,
          ),
      ],
    );
  }

  Widget _desktop(BuildContext context, String? routeName, bool immersive) {
    final destination = destinationForRoute(routeName);
    final playerBar = _playerBarFor(routeName);
    final queueBar = chrome.queueBar;
    final content = Column(
      children: [
        Expanded(child: chrome.child),
        if (!immersive && queueBar != null) queueBar,
        if (!immersive && playerBar != null) playerBar,
      ],
    );
    final useRail = AppResponsive.of(context).useNavigationRail;
    if (immersive || destination == null || !useRail) return content;
    return Row(
      children: [
        AppNavigationRail(
          key: const ValueKey('app-navigation-rail'),
          selected: destination,
          onSelect: chrome.onSelectDestination,
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: content),
      ],
    );
  }
}
