import 'package:flutter/foundation.dart';

/// How the app writes its keyboard shortcuts in labels and tooltips (D-065).
///
/// Apple keyboards say ⌘ where the others say Ctrl, so a hint that names the
/// wrong one sends the user hunting for a key that does nothing.
abstract final class AppCommandKeys {
  /// Whether [platform] (the current one when null) uses ⌘ for commands.
  static bool isApple([TargetPlatform? platform]) {
    final target = platform ?? defaultTargetPlatform;
    return target == TargetPlatform.macOS || target == TargetPlatform.iOS;
  }

  /// The command modifier as written in a key chip: ⌘ or Ctrl.
  static String modifier([TargetPlatform? platform]) =>
      isApple(platform) ? '⌘' : 'Ctrl';

  /// [key] with the command modifier, as written in running text: "⌘K" on
  /// Apple platforms, "Ctrl+K" elsewhere.
  static String withCommand(String key, [TargetPlatform? platform]) =>
      isApple(platform) ? '⌘$key' : 'Ctrl+$key';

  /// The global search: Ctrl/⌘ + K.
  static String search([TargetPlatform? platform]) =>
      withCommand('K', platform);

  /// [label] followed by its shortcut, e.g. "搜索（Ctrl+K）".
  static String hint(String label, String keys) => '$label（$keys）';
}
