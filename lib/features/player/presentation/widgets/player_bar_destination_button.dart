import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/navigation/app_chrome_scope.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/widgets/app_tap_pulse.dart';

/// The two library links of the desktop player bar.
enum PlayerBarLink {
  library,
  collections;

  String get label => switch (this) {
    PlayerBarLink.library => '音乐库',
    PlayerBarLink.collections => '收藏与播放列表',
  };

  IconData get icon => switch (this) {
    PlayerBarLink.library => Icons.library_music_outlined,
    PlayerBarLink.collections => Icons.collections_bookmark_outlined,
  };

  IconData get selectedIcon => switch (this) {
    PlayerBarLink.library => Icons.library_music_rounded,
    PlayerBarLink.collections => Icons.collections_bookmark_rounded,
  };

  /// Route the link opens.
  String get route => switch (this) {
    PlayerBarLink.library => Routes.library,
    PlayerBarLink.collections => Routes.collections,
  };

  Key get key => ValueKey('player-bar:link:$name');

  /// Whether [routeName] is a page this link leads to: the song, artist and
  /// album sections for 音乐库, favourites and playlists for 收藏与播放列表.
  bool isActiveFor(String? routeName) {
    if (routeName == null || routeName.isEmpty) return false;
    final path = Uri.parse(routeName).path;
    return switch (this) {
      PlayerBarLink.library =>
        path == Routes.library || path.startsWith('${Routes.library}/'),
      PlayerBarLink.collections =>
        path == Routes.collections || path == Routes.playlists,
    };
  }

  /// Whether pressing the link would only reopen the page already shown.
  bool isOpenAt(String? routeName) {
    if (routeName == null || routeName.isEmpty) return false;
    return Uri.parse(routeName).path == route;
  }
}

/// A player bar link that shows where it leads and answers every press.
///
/// The links were plain grey icon buttons: nothing marked the page the user
/// was on, and pressing the link to that page pushed a second copy of it,
/// which looked like nothing happened. Now the active link sits on the deep
/// lavender pill with its filled icon, every press gives a short pulse and a
/// selection click, and pressing the link to the page already open stays
/// there instead of stacking it again.
class PlayerBarDestinationButton extends StatefulWidget {
  const PlayerBarDestinationButton({
    super.key,
    required this.link,
    required this.currentRoute,
    required this.onOpen,
  });

  final PlayerBarLink link;

  /// The visible route, or null when unknown (nothing is highlighted).
  final String? currentRoute;

  /// Opens [PlayerBarLink.route].
  final VoidCallback onOpen;

  @override
  State<PlayerBarDestinationButton> createState() =>
      _PlayerBarDestinationButtonState();
}

class _PlayerBarDestinationButtonState
    extends State<PlayerBarDestinationButton> {
  int _presses = 0;

  void _press() {
    HapticFeedback.selectionClick();
    setState(() => _presses++);
    if (widget.link.isOpenAt(widget.currentRoute)) return;
    widget.onOpen();
  }

  static final ButtonStyle _style = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? AppColors.accentContainer
          : Colors.transparent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? AppColors.onAccentContainer
          : AppColors.textSecondary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final active = link.isActiveFor(widget.currentRoute);
    return Semantics(
      selected: active,
      child: AppTapPulse(
        trigger: _presses,
        child: IconButton(
          key: link.key,
          tooltip: link.label,
          isSelected: active,
          style: _style,
          onPressed: _press,
          icon: Icon(link.icon),
          selectedIcon: Icon(link.selectedIcon),
        ),
      ),
    );
  }
}

/// Both links side by side, following the visible route.
///
/// The route comes from [AppChromeScope], which the app shell installs around
/// its chrome; outside it (tests hosting a bar inside a route) nothing is
/// highlighted.
class PlayerBarLinks extends StatelessWidget {
  const PlayerBarLinks({super.key, required this.onOpen});

  final ValueChanged<PlayerBarLink> onOpen;

  @override
  Widget build(BuildContext context) {
    final routes = AppChromeScope.routeOf(context);
    if (routes == null) return _row(null);
    return ValueListenableBuilder<String?>(
      valueListenable: routes,
      builder: (context, route, _) => _row(route),
    );
  }

  Widget _row(String? route) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final link in PlayerBarLink.values)
          PlayerBarDestinationButton(
            link: link,
            currentRoute: route,
            onOpen: () => onOpen(link),
          ),
      ],
    );
  }
}
