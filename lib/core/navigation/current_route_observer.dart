import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tracks the top-most page route without notifying listeners during build.
///
/// Navigator can report its restored initial route while it is mounting. Route
/// observers therefore coalesce changes and publish the latest name after the
/// current frame, rather than synchronously rebuilding app-shell listeners.
class CurrentRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> _routeName = ValueNotifier<String?>(null);

  String? _pendingRouteName;
  bool _syncScheduled = false;

  ValueListenable<String?> get routeName => _routeName;

  void _sync(Route<dynamic>? route) {
    _pendingRouteName = route?.settings.name;
    if (_syncScheduled) return;

    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      final nextRouteName = _pendingRouteName;
      if (_routeName.value != nextRouteName) {
        _routeName.value = nextRouteName;
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute<dynamic>) _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic>) _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute<dynamic>) _sync(newRoute);
  }

  void dispose() => _routeName.dispose();
}
