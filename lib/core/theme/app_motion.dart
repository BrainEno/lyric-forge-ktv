import 'dart:io';

import 'package:flutter/widgets.dart';

/// Rules for the app's looping decorations: the spinning record and the
/// rhythm bars of the song that is playing (decision D-041).
///
/// One-off motion (a page transition, a press pulse) ends by itself. These
/// loop for as long as the music plays, so they answer to two switches the
/// one-off motion does not need:
///
///  * The system's "remove animations" setting, read through
///    [MediaQuery.maybeDisableAnimationsOf]. A record that keeps turning is exactly
///    the kind of motion that setting asks the app to stop.
///  * [ambientEnabled], off under `flutter test`. A loop schedules a frame on
///    every frame, so `pumpAndSettle` would never return on any screen that
///    shows a playing song. Tests that check the loop itself turn it back on
///    and restore it in a tear-down.
///
/// When either switch is off the decorations draw their resting pose: the
/// record still, the bars at mid height.
abstract final class AppMotion {
  /// Whether looping decorations may run at all.
  static bool ambientEnabled = !_underFlutterTest;

  static final bool _underFlutterTest = Platform.environment.containsKey(
    'FLUTTER_TEST',
  );

  /// Whether looping decorations should run below [context].
  static bool ambientOf(BuildContext context) =>
      ambientEnabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// One turn of the record: 33⅓ rpm, the speed of an LP.
  static const Duration recordTurn = Duration(milliseconds: 1800);

  /// One cycle of the rhythm bars.
  static const Duration rhythmCycle = Duration(milliseconds: 900);
}
