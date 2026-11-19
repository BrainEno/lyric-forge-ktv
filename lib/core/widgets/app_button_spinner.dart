import 'package:flutter/material.dart';

/// Small progress spinner for the icon slot of a busy button.
///
/// Takes the colour the button gives its icon, so it matches the label in
/// every state. Screens used to hard-code white, which is hard to see on the
/// accent fill (2.6:1) and brighter than the dimmed label once the button is
/// disabled while it works.
class AppButtonSpinner extends StatelessWidget {
  const AppButtonSpinner({super.key, this.size = defaultSize});

  /// Matches the 18 px icons used in buttons.
  static const double defaultSize = 18;

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
      ),
    );
  }
}
