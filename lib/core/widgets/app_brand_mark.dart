import 'package:flutter/material.dart';

import '../diagnostics/app_build_info.dart';
import '../theme/color_tokens.dart';

/// The app's brand mark: the fading equalizer from the app icon, with its one
/// Forge Red bar.
///
/// The navigation rail used to show Material's generic `graphic_eq` icon and
/// the dashboard header only the product name, so nothing in the interface
/// echoed the red, black and paper-white icon users click to open the app
/// (audit B-01). The mark is drawn rather than loaded from the icon file:
/// the file includes its light outer margin, which reads as a white tile on
/// the dark navigation.
///
/// The red appears here and nowhere else in the chrome; red text and red
/// states keep meaning "error" ([AppColors.error]).
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 28, this.semanticLabel});

  /// Height of the mark; it is [aspectRatio] times as wide.
  final double size;

  /// Spoken label; defaults to the product name. Pass an empty string when a
  /// visible name sits right beside the mark, so it is not read twice.
  final String? semanticLabel;

  /// Bar heights from left to right as fractions of [size], following the
  /// icon: one tall line, then shorter and shorter bars that fade to dots.
  static const List<double> barHeights = [1.0, 0.64, 0.44, 0.32, 0.12, 0.08];

  /// Bar widths in units of [size] / 14.
  static const List<double> barWidths = [0.6, 1.0, 1.2, 1.2, 1.2, 1.0];

  /// The bar drawn in Forge Red, as in the icon.
  static const int accentBar = 3;

  /// Gap between bars in units of [size] / 14.
  static const double barGap = 0.9;

  /// Width over height.
  static double get aspectRatio {
    final units =
        barWidths.fold<double>(0, (sum, width) => sum + width) +
        barGap * (barWidths.length - 1);
    return units / _unitsPerHeight;
  }

  static const double _unitsPerHeight = 14;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel ?? appDisplayName;
    final mark = SizedBox(
      width: size * aspectRatio,
      height: size,
      child: const CustomPaint(painter: _BrandMarkPainter()),
    );
    if (label.isEmpty) return ExcludeSemantics(child: mark);
    return Semantics(label: label, image: true, child: mark);
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / AppBrandMark._unitsPerHeight;
    final centerY = size.height / 2;
    var left = 0.0;
    for (var index = 0; index < AppBrandMark.barHeights.length; index++) {
      final width = AppBrandMark.barWidths[index] * unit;
      final height = AppBrandMark.barHeights[index] * size.height;
      final paint = Paint()
        ..color = index == AppBrandMark.accentBar
            ? AppColors.brand
            : AppColors.brandPaper;
      canvas.drawRect(
        Rect.fromLTWH(left, centerY - height / 2, width, height),
        paint,
      );
      left += width + AppBrandMark.barGap * unit;
    }
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}
