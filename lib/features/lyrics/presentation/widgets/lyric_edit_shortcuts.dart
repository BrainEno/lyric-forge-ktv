import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard bindings for the lyric editor.
///
/// They live in their own widget so the bindings can be exercised without
/// standing up the whole editor (project repository, playback service, audio
/// player). A shortcut that only works in a shipped build is a shortcut nobody
/// has verified.
class LyricEditShortcuts extends StatelessWidget {
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onSave;

  /// Opens document-wide find-and-replace: Ctrl+H, or Cmd+Shift+H on macOS
  /// where Cmd+H hides the app.
  final VoidCallback? onFindReplace;
  final Widget child;

  const LyricEditShortcuts({
    super.key,
    required this.onUndo,
    required this.onRedo,
    this.onSave,
    this.onFindReplace,
    required this.child,
  });

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    final findReplace = onFindReplace;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (save != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
        },
        if (findReplace != null) ...{
          // On Apple platforms Ctrl+H deletes backwards in text fields.
          if (!_isApple)
            const SingleActivator(LogicalKeyboardKey.keyH, control: true):
                findReplace,
          const SingleActivator(
            LogicalKeyboardKey.keyH,
            meta: true,
            shift: true,
          ): findReplace,
        },
        // Undo: Ctrl+Z on Windows/Linux, Cmd+Z on macOS.
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): onUndo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): onUndo,
        // Redo: both conventions are in use, so both are bound. Cmd+Shift+Z is
        // the macOS habit; Ctrl+Y is what Windows users reach for.
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): onRedo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            onRedo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): onRedo,
      },
      child: child,
    );
  }
}
