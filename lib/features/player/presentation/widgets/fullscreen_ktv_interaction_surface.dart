import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'global_playback_shortcuts.dart';

typedef FullscreenKtvSurfaceBuilder =
    Widget Function(BuildContext context, bool controlsVisible);

/// Interaction shell for immersive KTV playback.
///
/// It keeps keyboard/pointer behavior independent from playback state so the
/// full-screen UI can continue to use the single app-scoped playback session.
///
/// Keys, while the surface itself has focus:
///
/// * Esc: exit.
/// * Space: play / pause.
/// * ← / →, with or without Shift: skip back / forward
///   ([GlobalPlaybackShortcuts.seekStep]); held keys repeat.
/// * Ctrl (⌘ on macOS) + ← / →: previous / next song.
///
/// The app-wide shortcuts need Shift for seeking and let Space through only
/// when nothing is focused. Fullscreen KTV has no text to type into and keeps
/// focus on this surface, so it takes the bare keys a video player would.
/// Each command is handed to [onCommand], and a handled command shows the
/// controls so the progress bar confirms it. Any other key, a hover or a tap
/// only shows the controls.
class FullscreenKtvInteractionSurface extends StatefulWidget {
  final FullscreenKtvSurfaceBuilder builder;
  final VoidCallback onExit;
  final Duration controlsHideDelay;

  /// Runs a keyboard command; returns false when there was nothing to
  /// control, which leaves the key to the widgets above.
  final bool Function(GlobalPlaybackCommand command)? onCommand;

  const FullscreenKtvInteractionSurface({
    super.key,
    required this.builder,
    required this.onExit,
    this.onCommand,
    this.controlsHideDelay = const Duration(seconds: 3),
  });

  /// Key hints for the control layer, in the order of the class comment.
  static String keyHint({TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    final apple =
        target == TargetPlatform.macOS || target == TargetPlatform.iOS;
    final modifier = apple ? '⌘' : 'Ctrl+';
    final seconds = GlobalPlaybackShortcuts.seekStep.inSeconds;
    return '空格 播放/暂停 · ←/→ 后退/前进 $seconds 秒 · '
        '$modifier←/→ 上一首/下一首 · Esc 退出';
  }

  /// The command [event] maps to on this surface, or null.
  ///
  /// [surfaceFocused] is true while the surface itself, not one of its
  /// buttons, has the primary focus; only then does Space toggle playback,
  /// so a button reached with Tab still activates with Space.
  static GlobalPlaybackCommand? commandFor(
    KeyEvent event, {
    required HardwareKeyboard keyboard,
    required bool surfaceFocused,
  }) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    final shift = keyboard.isShiftPressed;
    final command = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (keyboard.isAltPressed) return null;

    if (key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent || shift || command) return null;
      return surfaceFocused ? GlobalPlaybackCommand.togglePlayPause : null;
    }
    final right = key == LogicalKeyboardKey.arrowRight;
    final left = key == LogicalKeyboardKey.arrowLeft;
    if (!right && !left) return null;
    if (command) {
      if (shift || event is KeyRepeatEvent) return null;
      return right
          ? GlobalPlaybackCommand.next
          : GlobalPlaybackCommand.previous;
    }
    return right
        ? GlobalPlaybackCommand.seekForward
        : GlobalPlaybackCommand.seekBack;
  }

  @override
  State<FullscreenKtvInteractionSurface> createState() =>
      _FullscreenKtvInteractionSurfaceState();
}

class _FullscreenKtvInteractionSurfaceState
    extends State<FullscreenKtvInteractionSurface> {
  late final FocusNode _focusNode;
  Timer? _hideTimer;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'fullscreen-ktv');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _scheduleHide();
    });
  }

  @override
  void didUpdateWidget(covariant FullscreenKtvInteractionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlsHideDelay != widget.controlsHideDelay) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.controlsHideDelay, () {
      if (!mounted || !_controlsVisible) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _revealControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHide();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    final onCommand = widget.onCommand;
    final command = onCommand == null
        ? null
        : FullscreenKtvInteractionSurface.commandFor(
            event,
            keyboard: HardwareKeyboard.instance,
            surfaceFocused: _focusNode.hasPrimaryFocus,
          );
    if (event is KeyDownEvent || command != null) _revealControls();
    if (command == null || !onCommand!(command)) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onTap() {
    // Clicking the lyrics takes the keys back from a button reached with Tab.
    if (!_focusNode.hasPrimaryFocus) _focusNode.requestFocus();
    _revealControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _revealControls(),
        onHover: (_) => _revealControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          onDoubleTap: widget.onExit,
          child: widget.builder(context, _controlsVisible),
        ),
      ),
    );
  }
}
