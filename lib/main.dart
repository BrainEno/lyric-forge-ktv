import 'dart:async';

import 'package:flutter/material.dart';

import 'core/layout/app_responsive.dart';
import 'core/navigation/app_chrome_controller.dart';
import 'core/navigation/app_router.dart';
import 'core/services/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'features/player/data/services/mobile_system_media_session.dart';
import 'features/player/presentation/widgets/global_player_bar.dart';
import 'features/player/presentation/widgets/mobile_global_player_bar.dart';
import 'features/transcription/presentation/widgets/global_transcription_queue_bar.dart';

final _appRouteObserver = _CurrentRouteObserver();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final services = ServiceLocatorGlobal.I;
  services.initialize();

  // The first Flutter frame must never depend on an optional native media
  // integration. AudioService/AVAudioSession can take time to initialise on a
  // physical iPhone (or fail because of a transient platform-channel issue).
  // Waiting here used to leave iOS sitting on the native white launch view with
  // no Flutter frame. Render the app first, then attach lock-screen/background
  // controls as a best-effort enhancement.
  runApp(const ElysiumPlayerApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeMobileMediaSessionAfterLaunch());
  });
}

Future<void> _initializeMobileMediaSessionAfterLaunch() async {
  final services = ServiceLocatorGlobal.I;
  try {
    await initializeMobileSystemMediaSession(
      playbackSession: services.playbackSessionService,
      audioPlayer: services.audioPlayerService,
    );
  } catch (error, stackTrace) {
    // Playback itself continues to work through just_audio. Failing to attach
    // system media controls must not blank or terminate the whole application.
    debugPrint('Mobile system media session initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class ElysiumPlayerApp extends StatefulWidget {
  const ElysiumPlayerApp({super.key});

  @override
  State<ElysiumPlayerApp> createState() => _ElysiumPlayerAppState();
}

class _ElysiumPlayerAppState extends State<ElysiumPlayerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncLocalLibraryAfterResume());
    }
  }

  Future<void> _syncLocalLibraryAfterResume() async {
    try {
      await ServiceLocatorGlobal.I.localMediaLibraryAutoSync.sync();
    } catch (error, stackTrace) {
      // Library maintenance must never prevent the app from resuming playback.
      debugPrint('Automatic local library sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopChrome = AppResponsive.isDesktopTarget();

    return MaterialApp(
      title: 'Elysium Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorObservers: <NavigatorObserver>[_appRouteObserver],
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: Routes.home,
      builder: (context, child) {
        return ValueListenableBuilder<String?>(
          valueListenable: _appRouteObserver.routeName,
          builder: (context, routeName, _) {
            final suppressPlayerBar = routeName == Routes.nowPlaying;

            if (!desktopChrome) {
              return ValueListenableBuilder<bool>(
                valueListenable: AppChromeController.immersive,
                builder: (context, immersive, _) {
                  final keyboardVisible =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  return Column(
                    children: [
                      Expanded(child: child ?? const SizedBox.shrink()),
                      if (!immersive &&
                          !keyboardVisible &&
                          !suppressPlayerBar)
                        const MobileGlobalPlayerBar(),
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
                        return Column(
                          children: [
                            Expanded(child: child ?? const SizedBox.shrink()),
                            if (!immersive) ...[
                              const GlobalTranscriptionQueueBar(),
                              if (!suppressPlayerBar)
                                const GlobalPlayerBar(),
                            ],
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

class _CurrentRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> routeName = ValueNotifier<String?>(null);

  void _sync(Route<dynamic>? route) {
    routeName.value = route?.settings.name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute<dynamic>) _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic>) _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute<dynamic>) _sync(newRoute);
  }
}
