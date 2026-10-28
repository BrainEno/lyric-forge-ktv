import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef FullscreenKtvSurfaceBuilder = Widget Function(
  BuildContext context,
  bool controlsVisible,
);

/// Interaction shell for immersive KTV playback.
///
/// It keeps keyboard/pointer behavior independent from playback state so the
/// full-screen UI can continue to use the single app-scoped playback session.
class FullscreenKtvInteractionSurface extends StatefulWidget {
  final FullscreenKtvSurfaceBuilder builder;
  final VoidCallback onExit;
  final Duration controlsHideDelay;

  const FullscreenKtvInteractionSurface({
    super.key,
    required this.builder,
    required this.onExit,
    this.controlsHideDelay = const Duration(seconds: 3),
  });

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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    _revealControls();
    return KeyEventResult.ignored;
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
          onTap: _revealControls,
          onDoubleTap: widget.onExit,
          child: widget.builder(context, _controlsVisible),
        ),
      ),
    );
  }
}
