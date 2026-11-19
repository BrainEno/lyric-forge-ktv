import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../domain/services/playback_session_service.dart';

/// What a global playback shortcut asks the session to do.
enum GlobalPlaybackCommand {
  togglePlayPause,
  next,
  previous,
  seekForward,
  seekBack,
}

/// App-wide keyboard shortcuts for the shared playback session.
///
/// * Space: play / pause, only while no particular control has focus, so a
///   focused button still activates with Space.
/// * Ctrl (⌘ on macOS) + → / ←: next / previous song.
/// * Shift + → / ←: skip 5 seconds forward / back.
///
/// Mounted once around the routed shell. Key events reach this widget only
/// after the focused widget declined them, so text fields (which keep Space
/// and arrows for typing and selection) and the lyric timing dialogs (which
/// own Space and the arrows while open) are never overridden. Hardware media
/// keys are deliberately left to the system media handler, which receives
/// them even when the window is in the background.
class GlobalPlaybackShortcuts extends StatelessWidget {
  const GlobalPlaybackShortcuts({
    super.key,
    required this.playbackSession,
    required this.child,
  });

  final PlaybackSessionService playbackSession;
  final Widget child;

  /// How far Shift + arrow moves the playhead.
  static const Duration seekStep = Duration(seconds: 5);

  /// Key hint shown after a control's label, e.g. "暂停（空格）".
  static String withHint(
    String label,
    GlobalPlaybackCommand command, {
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final apple =
        target == TargetPlatform.macOS || target == TargetPlatform.iOS;
    final modifier = apple ? '⌘' : 'Ctrl+';
    final keys = switch (command) {
      GlobalPlaybackCommand.togglePlayPause => '空格',
      GlobalPlaybackCommand.next => '$modifier→',
      GlobalPlaybackCommand.previous => '$modifier←',
      GlobalPlaybackCommand.seekForward => 'Shift+→',
      GlobalPlaybackCommand.seekBack => 'Shift+←',
    };
    return '$label（$keys）';
  }

  /// The command [event] maps to, or null when it is not a playback shortcut.
  ///
  /// [nothingFocused] is true while the primary focus is a focus scope rather
  /// than a specific control; only then does Space toggle playback.
  static GlobalPlaybackCommand? commandFor(
    KeyEvent event, {
    required HardwareKeyboard keyboard,
    required bool nothingFocused,
  }) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    final shift = keyboard.isShiftPressed;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    final alt = keyboard.isAltPressed;

    if (key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent || shift || command || alt) return null;
      return nothingFocused ? GlobalPlaybackCommand.togglePlayPause : null;
    }
    final right = key == LogicalKeyboardKey.arrowRight;
    final left = key == LogicalKeyboardKey.arrowLeft;
    if ((!right && !left) || alt) return null;
    if (command && !shift) {
      if (event is KeyRepeatEvent) return null;
      return right
          ? GlobalPlaybackCommand.next
          : GlobalPlaybackCommand.previous;
    }
    if (shift && !command) {
      return right
          ? GlobalPlaybackCommand.seekForward
          : GlobalPlaybackCommand.seekBack;
    }
    return null;
  }

  /// Runs [command] on [session]; returns false when there is nothing to
  /// control (empty queue, no next song), so the key is left unhandled.
  static bool run(
    GlobalPlaybackCommand command,
    PlaybackSessionService session,
  ) {
    final state = session.currentState;
    if (state.currentItem == null) return false;
    switch (command) {
      case GlobalPlaybackCommand.togglePlayPause:
        unawaited(session.togglePlayPause());
      case GlobalPlaybackCommand.next:
        if (!state.canSkipNext) return false;
        unawaited(session.skipNext());
      case GlobalPlaybackCommand.previous:
        if (!state.canSkipPrevious) return false;
        unawaited(session.skipPrevious());
      case GlobalPlaybackCommand.seekForward:
      case GlobalPlaybackCommand.seekBack:
        final playback = session.playbackState;
        final step = command == GlobalPlaybackCommand.seekForward
            ? seekStep
            : -seekStep;
        var target = playback.position + step;
        final duration = playback.duration;
        if (duration != null && target > duration) target = duration;
        if (target < Duration.zero) target = Duration.zero;
        unawaited(session.seek(target));
    }
    return true;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final command = commandFor(
      event,
      keyboard: HardwareKeyboard.instance,
      nothingFocused: FocusManager.instance.primaryFocus is FocusScopeNode,
    );
    if (command == null) return KeyEventResult.ignored;
    return run(command, playbackSession)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
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
