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
  await services.initializeSystemMediaControls();
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
