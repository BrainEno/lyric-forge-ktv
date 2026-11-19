import 'package:flutter/material.dart';

/// Gives a press a visible answer: [child] swells briefly and settles back
/// each time [trigger] changes.
///
/// Navigation entries and link buttons used to answer a press only with the
/// ink ripple, which is faint on the dark surfaces and invisible when the
/// press leads nowhere new (the destination is already open). Callers bump
/// [trigger] on every press, so a repeated press still shows it registered.
///
/// The animation is skipped when the platform asks for reduced motion.
class AppTapPulse extends StatefulWidget {
  const AppTapPulse({
    super.key,
    required this.trigger,
    required this.child,
    this.peakScale = defaultPeakScale,
    this.duration = defaultDuration,
  });

  /// Any value; a change starts the pulse. Usually a press counter.
  final Object? trigger;

  final Widget child;

  /// Largest scale reached, at 40 % of [duration].
  final double peakScale;

  final Duration duration;

  static const double defaultPeakScale = 1.18;
  static const Duration defaultDuration = Duration(milliseconds: 280);

  /// Scale at [progress] (0 to 1) of a pulse that peaks at [peakScale]: a
  /// quick swell over the first 40 %, then an eased return to exactly 1.
  static double scaleAt(
    double progress, {
    double peakScale = defaultPeakScale,
  }) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0.4) {
      final rise = Curves.easeOut.transform(t / 0.4);
      return 1 + (peakScale - 1) * rise;
    }
    final fall = Curves.easeInOutCubic.transform((t - 0.4) / 0.6);
    return peakScale - (peakScale - 1) * fall;
  }

  @override
  State<AppTapPulse> createState() => _AppTapPulseState();
}

class _AppTapPulseState extends State<AppTapPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant AppTapPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.trigger == widget.trigger) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.scale(
        scale: AppTapPulse.scaleAt(
          _controller.value,
          peakScale: widget.peakScale,
        ),
        child: child,
      ),
    );
  }
}
