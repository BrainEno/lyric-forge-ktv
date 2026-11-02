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
  final Widget child;

  const LyricEditShortcuts({
    super.key,
    required this.onUndo,
    required this.onRedo,
    this.onSave,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final save = onSave;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (save != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
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
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): onRedo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): onRedo,
      },
      child: child,
    );
  }
}
