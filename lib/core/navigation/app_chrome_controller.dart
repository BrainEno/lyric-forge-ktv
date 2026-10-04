import 'package:flutter/foundation.dart';

/// Controls app-level chrome that lives outside the Navigator.
///
/// Full-screen presentation surfaces (for example KTV mode) can temporarily
/// hide the persistent transcription/player bars without creating a second
/// playback stack or mutating route state.
abstract final class AppChromeController {
  static final ValueNotifier<bool> immersive = ValueNotifier<bool>(false);

  static void enterImmersive() {
    immersive.value = true;
  }

  static void exitImmersive() {
    immersive.value = false;
  }
}
