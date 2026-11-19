import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What the app chrome needs from the navigator it sits beside.
///
/// The player bars, the transcription queue bar and the persistent navigation
/// are built in `MaterialApp.builder`, around the navigator rather than inside
/// it. `Navigator.of(context)` from there finds nothing, so every push, dialog
/// and menu opened from a player bar threw "Navigator operation requested with
/// a context that does not include a Navigator", and the gesture handler
/// swallowed the error: pressing 音乐库 or 收藏与播放列表 in the bar, or the title
/// to open the full player, did nothing at all.
///
/// The app shell installs this scope around its chrome. Chrome widgets go
/// through [navigatorOf], [contextOf] and [pushNamed], which use the nearest
/// navigator when there is one (screens, and tests that host a bar inside a
/// route) and the app navigator otherwise.
class AppChromeScope extends InheritedWidget {
  const AppChromeScope({
    super.key,
    required this.navigatorKey,
    required this.currentRoute,
    required super.child,
  });

  /// Key of the app navigator.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Name of the visible route, published by the app's route observer.
  final ValueListenable<String?> currentRoute;

  static AppChromeScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppChromeScope>();

  /// The navigator that [context] should push onto.
  static NavigatorState? navigatorOf(BuildContext context) {
    return Navigator.maybeOf(context) ??
        maybeOf(context)?.navigatorKey.currentState;
  }

  /// A context under the navigator, for dialogs, sheets and snack bars opened
  /// from the chrome. Falls back to [context] itself when no navigator can be
  /// found, so callers never have to handle null.
  static BuildContext contextOf(BuildContext context) {
    if (Navigator.maybeOf(context) != null) return context;
    return maybeOf(context)?.navigatorKey.currentContext ?? context;
  }

  /// The visible route, or null outside the app shell.
  static ValueListenable<String?>? routeOf(BuildContext context) =>
      maybeOf(context)?.currentRoute;

  /// Pushes [routeName]. Returns null when there is no navigator to push onto.
  static Future<T?>? pushNamed<T extends Object?>(
    BuildContext context,
    String routeName,
  ) {
    return navigatorOf(context)?.pushNamed<T>(routeName);
  }

  @override
  bool updateShouldNotify(AppChromeScope oldWidget) =>
      navigatorKey != oldWidget.navigatorKey ||
      currentRoute != oldWidget.currentRoute;
}
