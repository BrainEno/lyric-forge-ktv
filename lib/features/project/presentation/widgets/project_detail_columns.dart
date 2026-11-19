import 'package:flutter/material.dart';

/// Arranges the project page below its hero: the lyric and progress cards
/// ([main]) beside the actions and metadata ([side]), or stacked with the
/// actions first when there is no room.
///
/// The page used to pick two columns from the window width (1080+). Inside
/// the app shell the rail and the page gutters already take 100–150 px, so
/// a 1100 px window squeezed two columns into ~950 px while a phone-sized
/// window could not tell. The choice now follows the width this widget is
/// actually given (audit P-03).
class ProjectDetailColumns extends StatelessWidget {
  const ProjectDetailColumns({
    super.key,
    required this.main,
    required this.side,
    required this.gap,
  });

  /// Below this content width the two columns stack.
  static const double twoColumnMinWidth = 880;

  /// The side column takes about a third of the row, within these bounds,
  /// so action buttons never get narrower than they are on a phone and the
  /// lyric card keeps most of a wide window.
  static const double minSideWidth = 320;
  static const double maxSideWidth = 440;

  static const Key mainKey = ValueKey('project-detail-main');
  static const Key sideKey = ValueKey('project-detail-side');

  final Widget main;
  final Widget side;
  final double gap;

  static bool useTwoColumns(double width) => width >= twoColumnMinWidth;

  static double sideWidthFor(double width) {
    return (width * 0.34).clamp(minSideWidth, maxSideWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mainColumn = KeyedSubtree(key: mainKey, child: main);
        final sideColumn = KeyedSubtree(key: sideKey, child: side);
        if (!useTwoColumns(width)) {
          // Stacked, the actions come first: on a phone the next step
          // matters more than the lyric statistics.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sideColumn,
              SizedBox(height: gap),
              mainColumn,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: mainColumn),
            SizedBox(width: gap),
            SizedBox(width: sideWidthFor(width), child: sideColumn),
          ],
        );
      },
    );
  }
}
