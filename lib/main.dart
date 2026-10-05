import 'dart:async';

import 'package:flutter/material.dart';

import 'core/layout/app_responsive.dart';
import 'core/navigation/app_chrome_controller.dart';
import 'core/navigation/app_router.dart';
import 'core/services/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'features/player/data/services/mobile_system_media_session.dart';
import 'features/player/presentation/widgets/global_player_bar.dart';
import 'features/transcription/presentation/widgets/global_transcription_queue_bar.dart';

final ValueNotifier<String?> _currentRouteName = ValueNotifier<String?>(
  Routes.home,
);
final NavigatorObserver _chromeRouteObserver = _ChromeRouteObserver(
  _currentRouteName,
);

class _ChromeRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> routeName;

  _ChromeRouteObserver(this.routeName);

  void _sync(Route<dynamic>? route) {
    final nextName = route?.settings.name;
    if (nextName != null && routeName.value != nextName) {
      routeName.value = nextName;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _sync(newRoute);
  }
}

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
  runApp(const LyricForgeApp());
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

class LyricForgeApp extends StatelessWidget {
  const LyricForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final desktopChrome = AppResponsive.isDesktopTarget();

    return MaterialApp(
      title: 'LyricForge KTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: Routes.home,
      navigatorObservers:
          desktopChrome ? [_chromeRouteObserver] : const <NavigatorObserver>[],
      builder: (context, child) {
        // The global player/transcription chrome is desktop-only. On iOS and
        // Android the previous extra Overlay/Column wrapper added no visible UI
        // but still sat between MaterialApp and its Navigator. Keep the mobile
        // widget tree conventional and let the Navigator render directly.
        if (!desktopChrome) {
          return child ?? const SizedBox.shrink();
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
                        if (!immersive)
                          ValueListenableBuilder<String?>(
                            valueListenable: _currentRouteName,
                            builder: (context, routeName, _) {
                              final isDashboard = routeName == Routes.home ||
                                  routeName == Routes.dashboard;
                              final ownsPlaybackControls = isDashboard ||
                                  routeName == Routes.quickPlay ||
                                  routeName == Routes.nowPlaying ||
                                  (routeName?.endsWith('/player') ?? false);

                              if (isDashboard && ownsPlaybackControls) {
                                return const SizedBox.shrink();
                              }

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isDashboard)
                                    const GlobalTranscriptionQueueBar(),
                                  if (!ownsPlaybackControls)
                                    const GlobalPlayerBar(),
                                ],
                              );
                            },
                          ),
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
  }
}
