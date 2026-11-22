import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/color_tokens.dart';

/// A vinyl record with a song's cover as its centre label (decision D-041).
///
/// The phone is first of all an offline player, so the song that is playing
/// is drawn as the thing it is: a record that turns while the music plays
/// and stops — at the angle it had reached, like a real turntable — when it
/// pauses. The listening home shows it large; the mini player and the
/// playing row show the same record small.
///
/// Pure decoration: it is excluded from semantics, and the widget around it
/// says what is playing. It stops turning when the system asks for reduced
/// motion and under `flutter test` (see [AppMotion]).
class AppVinylDisc extends StatefulWidget {
  const AppVinylDisc({
    super.key,
    required this.size,
    this.label,
    this.spinning = false,
    this.glow = false,
    this.labelFraction = defaultLabelFraction,
  });

  /// Diameter of the record.
  final double size;

  /// The centre label, usually the song's cover. Clipped to a circle; a
  /// brass note on a warm label stands in when it is null.
  final Widget? label;

  /// Whether the record turns. It only does while [AppMotion.ambientOf]
  /// allows looping motion.
  final bool spinning;

  /// A warm brass halo behind the record, for the large hero record.
  final bool glow;

  /// Label diameter as a fraction of [size].
  final double labelFraction;

  static const double defaultLabelFraction = 0.46;

  /// Grooves drawn on a record of [size]: one per six logical pixels between
  /// the label and the rim, never fewer than three, so the small record in a
  /// row still reads as a record and the large one is not a grey smear.
  static int grooveCountFor(
    double size, {
    double labelFraction = defaultLabelFraction,
  }) {
    final band = size / 2 * (0.96 - labelFraction);
    return math.max(3, (band / 6).floor());
  }

  @override
  State<AppVinylDisc> createState() => _AppVinylDiscState();
}

class _AppVinylDiscState extends State<AppVinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: AppMotion.recordTurn,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AppVinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Starts or stops the turn. A stop keeps the angle, so a paused record
  /// does not snap back to where it started.
  void _sync() {
    final run = widget.spinning && AppMotion.ambientOf(context);
    if (run && !_turns.isAnimating) {
      _turns.repeat();
    } else if (!run && _turns.isAnimating) {
      _turns.stop();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final labelSize = size * widget.labelFraction;
    final ring = math.max(1.0, size * 0.012);
    final label = widget.label;

    final record = CustomPaint(
      painter: _RecordPainter(
        centerColor: AppColors.vinylDiscCenter,
        edgeColor: AppColors.borderSubtle,
        grooves: AppVinylDisc.grooveCountFor(
          size,
          labelFraction: widget.labelFraction,
        ),
        labelFraction: widget.labelFraction,
      ),
      child: Center(
        child: Container(
          width: labelSize,
          height: labelSize,
          padding: EdgeInsets.all(ring),
          // The ring sits on the black record in every theme, so it keeps
          // the light brass (D-042).
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.vinylAccentOnDark,
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                label ?? _BlankLabel(size: labelSize),
                // The spindle hole: what makes a round cover read as a
                // record label rather than an avatar.
                Center(
                  child: Container(
                    width: math.max(3.0, size * 0.035),
                    height: math.max(3.0, size * 0.035),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bgBase,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.glow)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.vinylAccentMuted,
                        blurRadius: size * 0.22,
                        spreadRadius: size * 0.02,
                      ),
                    ],
                  ),
                ),
              ),
            Positioned.fill(
              child: RotationTransition(turns: _turns, child: record),
            ),
            // The light does not turn with the record, which is what sells
            // the motion: the grooves slide under a still reflection.
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SheenPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The label of a record whose song has no cover.
class _BlankLabel extends StatelessWidget {
  const _BlankLabel({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.vinylSurfaceHigh,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.42,
        color: AppColors.vinylAccent,
      ),
    );
  }
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter({
    required this.centerColor,
    required this.edgeColor,
    required this.grooves,
    required this.labelFraction,
  });

  /// Where the radial gradient starts and the hairline round the edge; both
  /// come from the theme, so a theme change repaints the record.
  final Color centerColor;
  final Color edgeColor;
  final int grooves;
  final double labelFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final disc = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [centerColor, AppColors.vinylDisc],
          stops: const [0.3, 1],
        ).createShader(disc),
    );

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, radius * 0.008)
      ..color = AppColors.vinylGroove;
    final inner = radius * (labelFraction + 0.04);
    final outer = radius * 0.94;
    for (var i = 0; i < grooves; i++) {
      final t = grooves == 1 ? 0.5 : i / (grooves - 1);
      canvas.drawCircle(center, inner + (outer - inner) * t, groove);
    }

    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edgeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _RecordPainter oldDelegate) =>
      oldDelegate.centerColor != centerColor ||
      oldDelegate.edgeColor != edgeColor ||
      oldDelegate.grooves != grooves ||
      oldDelegate.labelFraction != labelFraction;
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Colors.transparent,
            AppColors.vinylSheen,
            Colors.transparent,
            Colors.transparent,
            AppColors.vinylSheen,
            Colors.transparent,
          ],
          stops: [0.04, 0.12, 0.2, 0.54, 0.62, 0.7],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SheenPainter oldDelegate) => false;
}

/// Three rhythm bars that bounce while a song plays: the "this one" mark of
/// the playing row and of the listening home.
///
/// A paused song keeps the mark, so it still shows which one it is, but the
/// bars drop to a low, even, faded row ([pausedHeights]): paused bars used to
/// stand at the same staggered heights as a frame of the bounce, which read
/// as still playing (D-059). When looping motion is off (see [AppMotion]) or
/// under `flutter test`, a playing song shows the staggered [stillHeights]
/// instead of the bounce. Excluded from semantics; the row says 正在播放 or
/// 已暂停 in words.
class AppRhythmBars extends StatefulWidget {
  const AppRhythmBars({
    super.key,
    required this.playing,
    this.size = 18,
    this.color,
  });

  final bool playing;

  /// Width and height of the square the bars stand in.
  final double size;

  /// Defaults to [AppColors.vinylAccent] of the theme in use.
  final Color? color;

  /// Number of bars.
  static const int barCount = 3;

  /// Height of bar [index] as a fraction of the full height at [phase]
  /// (0 to 1 over one cycle). Each bar runs on its own offset so they never
  /// line up, and never drops below a quarter, so a bar never disappears.
  static double heightAt(int index, double phase) {
    final offset = index * 0.37;
    final wave = math.sin((phase + offset) * 2 * math.pi);
    return 0.25 + 0.75 * (wave + 1) / 2;
  }

  /// A playing song without motion: low, high, middle.
  static const List<double> stillHeights = [0.45, 0.85, 0.6];

  /// A paused song: all three bars low and level.
  static const List<double> pausedHeights = [0.3, 0.3, 0.3];

  /// Opacity of the bars of a paused song.
  static const double pausedOpacity = 0.6;

  @override
  State<AppRhythmBars> createState() => _AppRhythmBarsState();
}

class _AppRhythmBarsState extends State<AppRhythmBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: AppMotion.rhythmCycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AppRhythmBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.playing && AppMotion.ambientOf(context);
    if (run && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!run && _phase.isAnimating) {
      _phase.stop();
      _phase.value = 0;
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final gap = size / 8;
    final barWidth =
        (size - gap * (AppRhythmBars.barCount - 1)) / AppRhythmBars.barCount;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _phase,
          builder: (context, _) {
            final moving = _phase.isAnimating;
            final still = widget.playing
                ? AppRhythmBars.stillHeights
                : AppRhythmBars.pausedHeights;
            final bars = Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < AppRhythmBars.barCount; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Container(
                    width: barWidth,
                    height:
                        size *
                        (moving
                            ? AppRhythmBars.heightAt(i, _phase.value)
                            : still[i]),
                    decoration: BoxDecoration(
                      color: widget.color ?? AppColors.vinylAccent,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(barWidth / 2),
                      ),
                    ),
                  ),
                ],
              ],
            );
            return widget.playing
                ? bars
                : Opacity(opacity: AppRhythmBars.pausedOpacity, child: bars);
          },
        ),
      ),
    );
  }
}

/// A song's cover, blurred into a warm wash behind the content above it.
///
/// Gives the listening home the colour of the record that is on without a
/// palette extractor: the cover itself, heavily blurred and faded into the
/// page. Without a cover the warm vinyl gradient stands in.
class AppCoverGlow extends StatelessWidget {
  const AppCoverGlow({super.key, required this.cover, required this.child});

  /// The cover to blur, usually an [AppArtwork]; null for the plain warm
  /// gradient.
  final Widget? cover;
  final Widget child;

  /// Blur radius of the cover.
  static const double blurSigma = 48;

  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.vinylHeroGradient),
          ),
        ),
        if (cover != null)
          Positioned.fill(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 0.42,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: cover,
                ),
              ),
            ),
          ),
        // Fade the bottom into the page so the shelves below sit on the
        // plain background.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.bgBase],
                  stops: [0.55, 1],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
