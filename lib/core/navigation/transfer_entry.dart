import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import 'routes.dart';

/// The way into device transfer: one name, one icon, one route rule.
///
/// Transfer used to have four entries (library strip, a floating button, the
/// dashboard header and the player bar menu) under different names, 跨设备传输
/// in the library and 远程音乐库 with a cast icon on the dashboard, for a
/// task most people do now and then (audit L-02). Two remain: the button at
/// the end of the library's section strip, and an item in the dashboard's
/// 更多 menu. Both use this name, icon and route, and both transfer screens
/// carry the same title, so the entry and the page it opens agree.
abstract final class TransferEntry {
  /// Button tooltip, menu item and screen title.
  static const String label = '跨设备传输';

  static const IconData icon = Icons.devices_rounded;

  /// Value of the dashboard's 更多 menu item.
  static const String menuValue = 'transfer';

  /// The desktop shares its library and receives songs; a phone connects to
  /// a desktop and browses it.
  static String routeFor({required bool desktop}) =>
      desktop ? Routes.mediaSharing : Routes.remoteLibrary;

  /// Pushes the transfer screen for this device, or for [desktop] when given.
  static Future<void> open(BuildContext context, {bool? desktop}) {
    final route = routeFor(desktop: desktop ?? AppResponsive.isDesktopTarget());
    return Navigator.pushNamed(context, route);
  }
}
