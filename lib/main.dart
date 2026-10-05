import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/navigation/app_chrome_controller.dart';
import 'core/navigation/app_router.dart';
import 'core/services/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'features/player/presentation/widgets/global_player_bar.dart';
import 'features/transcription/presentation/widgets/global_transcription_queue_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = ServiceLocatorGlobal.I;
  services.initialize();
  try {
    await services.initializeSystemMediaControls();
  } catch (error, stackTrace) {
    // Playback inside the app should still be available if the platform media
    // service cannot initialise on a particular device/build configuration.
    debugPrint('System media controls unavailable: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
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
