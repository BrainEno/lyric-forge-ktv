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

class ElysiumPlayerApp extends StatelessWidget {
  const ElysiumPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final desktopChrome = AppResponsive.isDesktopTarget();

    return MaterialApp(
      title: 'Elysium Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: Routes.home,
      builder: (context, child) {
        // Keep the global playback/transcription chrome desktop-only. Mobile
        // renders the Navigator directly so native launch and media-session
        // startup stay independent from desktop UI chrome.
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
                        if (!immersive) ...[
                          const GlobalTranscriptionQueueBar(),
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
  }
}
