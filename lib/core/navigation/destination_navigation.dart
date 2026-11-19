import 'package:flutter/widgets.dart';

import 'app_destinations.dart';
import 'routes.dart';

/// What pressing a top-level destination should do.
enum DestinationTap {
  /// The user is already on the destination's first page. Pushing it again
  /// only replayed the page transition and reset its scroll position, which
  /// felt like the press had been ignored; the navigation answers with its own
  /// press animation instead.
  stay,

  /// Somewhere else, or deeper inside the destination: go to its first page.
  open,
}

/// Paths that count as the first page of [destination].
Set<String> _rootPaths(AppDestination destination) => switch (destination) {
  AppDestination.projects => {Routes.home, Routes.dashboard},
  AppDestination.library => {Routes.library},
  AppDestination.review => {Routes.review},
  AppDestination.settings => {Routes.settings},
};

/// Decides what a press on [destination] does while [currentRoute] is shown.
DestinationTap planDestinationTap(
  AppDestination destination,
  String? currentRoute,
) {
  if (currentRoute == null || currentRoute.isEmpty) return DestinationTap.open;
  final path = Uri.parse(currentRoute).path;
  return _rootPaths(destination).contains(path)
      ? DestinationTap.stay
      : DestinationTap.open;
}

/// Sends the user to [destination] from anywhere.
///
/// 「工程」 is the root route, so it pops back to it instead of stacking another
/// copy; the other three are pushed on top of the root so that one press of
/// back returns to the previous place rather than exiting the app. Returns
/// what it did.
DestinationTap goToDestination(
  NavigatorState navigator,
  AppDestination destination,
  String? currentRoute,
) {
  final plan = planDestinationTap(destination, currentRoute);
  if (plan == DestinationTap.stay) return plan;
  if (destination == AppDestination.projects) {
    navigator.popUntil((route) => route.isFirst);
  } else {
    navigator.pushNamedAndRemoveUntil(
      destination.route,
      (route) => route.isFirst,
    );
  }
  return plan;
}
