import 'package:flutter/material.dart';

import '../core/layout/app_responsive.dart';
import '../core/navigation/app_chrome_controller.dart';
import '../core/navigation/app_destinations.dart';
import '../core/navigation/app_navigation_shell.dart';
import '../core/navigation/current_route_observer.dart';
import '../core/navigation/routes.dart';
import '../core/theme/app_theme.dart';
import '../features/player/presentation/widgets/global_player_bar.dart';
import '../features/player/presentation/widgets/mobile_global_player_bar.dart';
import '../features/player/presentation/widgets/playback_lyrics_availability_sync.dart';
import '../features/transcription/presentation/widgets/global_transcription_queue_bar.dart';
import 'app_router.dart';
import 'app_services.dart';

final _appRouteObserver = CurrentRouteObserver();

/// Needed because the navigation shell lives *outside* the navigator: it wraps
/// the whole app, so `Navigator.of(context)` from there finds nothing.
final _navigatorKey = GlobalKey<NavigatorState>();

/// Sends the user to a top-level destination from anywhere.
///
/// 「工程」 is the root route, so it pops back to it instead of stacking another
/// copy; the other three are pushed on top of the root so that one press of
/// back returns to the previous place rather than exiting the app.
void _goToDestination(AppDestination destination) {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  if (destination == AppDestination.projects) {
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  navigator.pushNamedAndRemoveUntil(
    destination.route,
    (route) => route.isFirst,
  );
}

/// The app shell: theme, navigator, routing table and the chrome around it.
///
/// Moved out of `lib/main.dart` in Phase 4.2 so that `main.dart` is only
/// bootstrap (create services, run the app) and this file is the widget tree.
/// [services] is optional so tests can build the shell without initialising
/// real audio/ASR dependencies; when omitted the process-wide instance is used,
/// which is exactly what production does.
class ElysiumPlayerApp extends StatelessWidget {
  final bool? desktopChromeOverride;
  final AppServices? services;

  const ElysiumPlayerApp({super.key, this.desktopChromeOverride, this.services});

  @override
  Widget build(BuildContext context) {
    final desktopChrome =
        desktopChromeOverride ?? AppResponsive.isDesktopTarget();
    final router = AppRouter(services ?? AppServices.instance);

    return MaterialApp(
      title: 'Elysium Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: _navigatorKey,
      navigatorObservers: <NavigatorObserver>[_appRouteObserver],
      onGenerateRoute: router.onGenerateRoute,
      initialRoute: Routes.home,
      builder: (context, child) {
        // Keep the queue's lyric flag aligned with the resolved lyric project
        // for the current song, whichever route is visible.
        final syncedShell = PlaybackLyricsAvailabilitySync(
          child: child ?? const SizedBox.shrink(),
        );
        return ValueListenableBuilder<String?>(
          valueListenable: _appRouteObserver.routeName,
          builder: (context, routeName, _) {
            final suppressPlayerBar = routeName == Routes.nowPlaying;
            // The four top-level destinations are always one press away; the
            // immersive player and the KTV view are the two places where a
            // persistent rail would cover what the user is watching.
            final showNavigation = destinationForRoute(routeName) != null;
            final selectedDestination = destinationForRoute(routeName);
            final layout = AppResponsive.of(context);
            final useRail = layout.useNavigationRail;

            if (!desktopChrome) {
              return ValueListenableBuilder<bool>(
                valueListenable: AppChromeController.immersive,
                builder: (context, immersive, _) {
                  final keyboardVisible =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  final showChrome = !immersive && !keyboardVisible;
                  return Column(
                    children: [
                      Expanded(child: syncedShell),
                      if (showChrome && !suppressPlayerBar)
                        const MobileGlobalPlayerBar(),
                      if (showChrome && showNavigation)
                        AppBottomNavigation(
                          selected: selectedDestination!,
                          onSelect: _goToDestination,
                        ),
                    ],
                  );
                },
              );
            }

            return Overlay(
              clipBehavior: Clip.none,
              initialEntries: [
                OverlayEntry(
                  builder: (overlayContext) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: AppChromeController.immersive,
                      builder: (context, immersive, _) {
                        final content = Column(
                          children: [
                            Expanded(child: syncedShell),
                            if (!immersive) ...[
                              const GlobalTranscriptionQueueBar(),
                              if (!suppressPlayerBar) const GlobalPlayerBar(),
                            ],
                          ],
                        );
                        if (immersive || !showNavigation || !useRail) {
                          return content;
                        }
                        return Row(
                          children: [
                            AppNavigationRail(
                              selected: selectedDestination,
                              onSelect: _goToDestination,
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(child: content),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
