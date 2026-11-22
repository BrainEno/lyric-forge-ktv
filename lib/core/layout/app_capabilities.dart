import 'package:flutter/foundation.dart';

import 'app_responsive.dart';

/// What this device can do, as opposed to how wide its window is.
///
/// A phone cannot run the recognition models (decision D-058). So the whole
/// lyric workbench — importing a song for recognition, the project list, the
/// lyric editor with its proofreading and the AI 识别 settings — is a desktop
/// feature. On a phone, a song gets lyrics from the internet, from a lyric file
/// (LRC or TXT), from pasted plain text, or from the computer, and the player
/// shows them.
abstract final class AppCapabilities {
  /// Lets a test pretend to be a phone or a desktop.
  @visibleForTesting
  static bool? debugLyricWorkbenchOverride;

  /// Whether recognition, projects and the lyric editor are offered here.
  static bool get lyricWorkbench =>
      debugLyricWorkbenchOverride ?? AppResponsive.isDesktopTarget();
}
