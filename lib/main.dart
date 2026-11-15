import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'features/player/data/services/mobile_system_media_session.dart';

/// Process bootstrap: build the services, then run the app.
///
/// Everything else moved in Phase 4.2 — the widget tree lives in `lib/app/app.dart`
/// and the routing table in `lib/app/app_router.dart`, so this file no longer
/// imports a screen.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledDataLicenses();

  final services = AppServices.instance;
  services.initialize();

  // The first Flutter frame must never depend on an optional native media
  // integration. AudioService/AVAudioSession can take time to initialise on a
  // physical iPhone (or fail because of a transient platform-channel issue).
  // Waiting here used to leave iOS sitting on the native white launch view with
  // no Flutter frame. Render the app first, then attach lock-screen/background
  // controls as a best-effort enhancement.
  runApp(ElysiumPlayerApp(services: services));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeMobileMediaSessionAfterLaunch(services));
  });
}

Future<void> _initializeMobileMediaSessionAfterLaunch(
  AppServices services,
) async {
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

/// Data files bundled without a Dart package carry their notices here, so the
/// license page lists them next to the package licenses.
void _registerBundledDataLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('third_party/opencc/LICENSE');
    yield LicenseEntryWithLineBreaks(const [
      'OpenCC (Chinese script tables)',
    ], text);
  });
}
