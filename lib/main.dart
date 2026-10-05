import 'package:flutter/material.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = ServiceLocatorGlobal.I;
  services.initialize();
  await initializeMobileSystemMediaSession(
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
  );

  runApp(const LyricForgeApp());
}

class LyricForgeApp extends StatelessWidget {
  const LyricForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LyricForge KTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: Routes.home,
      navigatorObservers: [_chromeRouteObserver],
      builder: (context, child) {
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
