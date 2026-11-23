import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What a global search shortcut asks for.
enum GlobalSearchCommand { search, shortcuts }

/// App-wide keys for the global search and the shortcut panel (D-065).
///
/// * Ctrl+K (⌘K on macOS): open the search, from any page, also while
///   typing in a field — no text field uses it. On macOS only ⌘ counts,
///   since Ctrl+K deletes to the end of the line there.
/// * Ctrl+/ (⌘/) or F1: open the shortcut panel.
/// * ?: the same, only while no control has focus, so it can still be typed.
///
/// Mounted once around the routed shell, like `GlobalPlaybackShortcuts`;
/// dialogs and focused widgets see their keys first.
class GlobalSearchShortcuts extends StatelessWidget {
  const GlobalSearchShortcuts({
    super.key,
    required this.onSearch,
    required this.onShortcuts,
    required this.child,
  });

  final VoidCallback onSearch;
  final VoidCallback onShortcuts;
  final Widget child;

  /// The command [event] maps to, or null when it is not one of these keys.
  ///
  /// [nothingFocused] is true while the primary focus is a focus scope
  /// rather than a specific control; only then does ? open the panel.
  static GlobalSearchCommand? commandFor(
    KeyEvent event, {
    required HardwareKeyboard keyboard,
    required bool nothingFocused,
    TargetPlatform? platform,
  }) {
    if (event is! KeyDownEvent) return null;
    if (keyboard.isAltPressed) return null;
    final target = platform ?? defaultTargetPlatform;
    final apple =
        target == TargetPlatform.macOS || target == TargetPlatform.iOS;
    final command = apple
        ? keyboard.isMetaPressed && !keyboard.isControlPressed
        : keyboard.isControlPressed && !keyboard.isMetaPressed;
    final key = event.logicalKey;
    if (command) {
      if (key == LogicalKeyboardKey.keyK && !keyboard.isShiftPressed) {
        return GlobalSearchCommand.search;
      }
      if (key == LogicalKeyboardKey.slash) return GlobalSearchCommand.shortcuts;
      return null;
    }
    if (keyboard.isControlPressed || keyboard.isMetaPressed) return null;
    if (key == LogicalKeyboardKey.f1) return GlobalSearchCommand.shortcuts;
    final question =
        event.character == '?' || key == LogicalKeyboardKey.question;
    if (question && nothingFocused) return GlobalSearchCommand.shortcuts;
    return null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final command = commandFor(
      event,
      keyboard: HardwareKeyboard.instance,
      nothingFocused: FocusManager.instance.primaryFocus is FocusScopeNode,
    );
    switch (command) {
      case null:
        return KeyEventResult.ignored;
      case GlobalSearchCommand.search:
        onSearch();
      case GlobalSearchCommand.shortcuts:
        onShortcuts();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: child,
    );
  }
}
