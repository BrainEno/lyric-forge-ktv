import 'dart:async';

import 'package:flutter/material.dart';

import '../core/layout/app_responsive.dart';
import '../core/navigation/app_chrome_controller.dart';
import '../core/navigation/app_destinations.dart';
import '../core/navigation/current_route_observer.dart';
import '../core/navigation/destination_navigation.dart';
import '../core/navigation/mobile_destinations.dart';
import '../core/navigation/routes.dart';
import '../core/theme/app_appearance.dart';
import '../core/theme/app_appearance_host.dart';
import '../core/theme/app_theme.dart';
import '../features/player/presentation/local_library_dependencies.dart';
import '../features/player/presentation/widgets/global_playback_shortcuts.dart';
import '../features/player/presentation/widgets/global_player_bar.dart';
import '../features/player/presentation/widgets/mobile_global_player_bar.dart';
import '../features/player/presentation/widgets/playback_lyrics_availability_sync.dart';
import '../features/search/presentation/global_search_dependencies.dart';
import '../features/search/presentation/widgets/global_search_palette.dart';
import '../features/search/presentation/widgets/global_search_shortcuts.dart';
import '../features/search/presentation/widgets/keyboard_shortcuts_panel.dart';
import '../features/transcription/presentation/widgets/global_transcription_queue_bar.dart';
import 'app_chrome.dart';
import 'app_router.dart';
import 'app_services.dart';
import 'local_library_assembly.dart';
import 'playback_assembly.dart';
import 'search_assembly.dart';

final _appRouteObserver = CurrentRouteObserver();

/// Needed because the navigation shell lives *outside* the navigator: it wraps
/// the whole app, so `Navigator.of(context)` from there finds nothing.
final _navigatorKey = GlobalKey<NavigatorState>();

/// Sends the user to a top-level destination from the rail or bottom bar.
/// Pressing the destination already on screen leaves the page alone; see
/// [planDestinationTap].
void _goToDestination(AppDestination destination) {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  goToDestination(navigator, destination, _appRouteObserver.routeName.value);
}

/// The same for the phone's bottom bar, whose destinations differ.
void _goToMobileDestination(MobileDestination destination) {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  goToMobileDestination(
    navigator,
    destination,
    _appRouteObserver.routeName.value,
  );
}

/// Opens [route] from the global search (D-065): a top-level destination the
/// way its rail button does, anything else on top of the current page.
void _openRoute(String route) {
  final navigator = _navigatorKey.currentState;
  if (navigator == null) return;
  final current = _appRouteObserver.routeName.value;
  for (final destination in AppDestination.values) {
    if (destination.route == route) {
      goToDestination(navigator, destination, current);
      return;
    }
  }
  if (route == current) return;
  unawaited(navigator.pushNamed<void>(route));
}

/// A context under the navigator for the search and the shortcut panel, or
/// null while fullscreen KTV is up: it keeps the keys for itself and has no
/// room for a dialog.
BuildContext? _dialogContext() {
  if (AppChromeController.immersive.value) return null;
  return _navigatorKey.currentContext;
}

void _openSearch(GlobalSearchDependencies dependencies) {
  final context = _dialogContext();
  if (context != null) unawaited(showGlobalSearch(context, dependencies));
}

void _showShortcuts() {
  final context = _dialogContext();
  if (context != null) unawaited(showKeyboardShortcuts(context));
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

  /// The theme controller; the services' one when null. Tests pass their own
  /// to switch themes without touching the process-wide services.
  final AppAppearanceController? appearance;

  const ElysiumPlayerApp({
    super.key,
    this.desktopChromeOverride,
    this.services,
    this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    final desktopChrome =
        desktopChromeOverride ?? AppResponsive.isDesktopTarget();
    final services = this.services ?? AppServices.instance;
    // The phone opens on the listening home instead of the project
    // dashboard (decision D-041).
    final router = AppRouter(services, listeningHome: !desktopChrome);
    // The two player bars are chrome, built by this shell rather than routed, so
    // they get their own bundle instead of reaching for the locator. Skipped
    // before bootstrap for the same reason the lyric sync is.
    final localLibrary = services.isInitialized
        ? assembleLocalLibraryDependencies(services)
        : null;
    // The global search and its keys (D-065), also skipped before bootstrap.
    final search = services.isInitialized
        ? assembleGlobalSearchDependencies(
            services,
            phone: !desktopChrome,
            openRoute: _openRoute,
          )
        : null;

    // The chosen theme (decision D-042): the host switches the palette that
    // AppColors reads and rebuilds everything below when it changes.
    return AppAppearanceHost(
      controller: appearance ?? services.appearance,
      builder: (context, variant) => _materialApp(
        services: services,
        router: router,
        localLibrary: localLibrary,
        search: search,
        desktopChrome: desktopChrome,
        theme: AppTheme.themeFor(variant.palette),
      ),
    );
  }

  Widget _materialApp({
    required AppServices services,
    required AppRouter router,
    required LocalLibraryDependencies? localLibrary,
    required GlobalSearchDependencies? search,
    required bool desktopChrome,
    required ThemeData theme,
  }) {
    return MaterialApp(
      title: 'Elysium Player',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // AppColors switches at once; a cross-fade of the Material theme alone
      // would leave the two disagreeing for a fifth of a second.
      themeAnimationDuration: Duration.zero,
      navigatorKey: _navigatorKey,
      navigatorObservers: <NavigatorObserver>[_appRouteObserver],
      onGenerateRoute: router.onGenerateRoute,
      initialRoute: Routes.home,
      builder: (context, child) {
        // Keep the queue's lyric flag aligned with the resolved lyric project
        // for the current song, whichever route is visible.
        //
        // Skipped when the shell is built without bootstrap (widget tests that
        // only inspect the MaterialApp): there is no session to listen to yet.
        final shell = child ?? const SizedBox.shrink();
        //
        // The global playback shortcuts sit inside it, around the routes, so
        // focused text fields and dialogs see their keys first.
        final openSearch = search == null ? null : () => _openSearch(search);
        // The phone has no keyboard to list shortcuts for.
        final showShortcuts = search != null && desktopChrome
            ? _showShortcuts
            : null;
        final syncedShell = services.isInitialized
            ? PlaybackLyricsAvailabilitySync(
                lyricsResolver: buildPlaybackLyricsResolver(services),
                playbackSession: services.playbackSessionService,
                child: GlobalPlaybackShortcuts(
                  playbackSession: services.playbackSessionService,
                  child: openSearch == null
                      ? shell
                      : GlobalSearchShortcuts(
                          onSearch: openSearch,
                          onShortcuts: showShortcuts ?? () {},
                          child: shell,
                        ),
                ),
              )
            : shell;
        return AppChrome(
          desktop: desktopChrome,
          navigatorKey: _navigatorKey,
          currentRoute: _appRouteObserver.routeName,
          onSelectDestination: _goToDestination,
          onSelectMobileDestination: _goToMobileDestination,
          onOpenSearch: openSearch,
          onShowShortcuts: showShortcuts,
          queueBar: desktopChrome && services.isInitialized
              ? GlobalTranscriptionQueueBar(queue: services.transcriptionQueue)
              : null,
          playerBar: localLibrary == null
              ? null
              : desktopChrome
              ? GlobalPlayerBar(dependencies: localLibrary)
              : MobileGlobalPlayerBar(dependencies: localLibrary),
          child: syncedShell,
        );
      },
    );
  }
}
