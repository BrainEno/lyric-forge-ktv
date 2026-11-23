import 'package:flutter/material.dart';

import '../navigation/app_chrome_scope.dart';
import '../navigation/app_command_keys.dart';

/// Opens the global search from a page header (D-065).
///
/// Pages show it without knowing the search feature: the app shell hands the
/// launcher down through [AppChromeScope]. Where there is none (widget tests,
/// or before the app has started) the button is not shown at all, rather
/// than shown and doing nothing.
class AppSearchButton extends StatelessWidget {
  const AppSearchButton({
    super.key,
    this.filledTonal = false,
    this.size,
    this.trailingGap = 0,
  });

  static const buttonKey = ValueKey('app-search-button');

  /// Drawn like the header's other tonal buttons.
  final bool filledTonal;

  /// Minimum edge of the button; the theme's default when null.
  final double? size;

  /// Space after the button, left out with it when there is no search.
  final double trailingGap;

  /// The tooltip, naming the shortcut on platforms with a keyboard.
  static String tooltipFor(TargetPlatform platform) {
    final keyboard =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    const label = '搜索工程、歌曲、歌单和操作';
    return keyboard
        ? AppCommandKeys.hint(label, AppCommandKeys.search(platform))
        : label;
  }

  @override
  Widget build(BuildContext context) {
    final open = AppChromeScope.searchOf(context);
    if (open == null) return const SizedBox.shrink();
    final tooltip = tooltipFor(Theme.of(context).platform);
    final style = size == null
        ? null
        : IconButton.styleFrom(minimumSize: Size.square(size!));
    const icon = Icon(Icons.search_rounded);
    final button = filledTonal
        ? IconButton.filledTonal(
            key: buttonKey,
            tooltip: tooltip,
            style: style,
            onPressed: open,
            icon: icon,
          )
        : IconButton(
            key: buttonKey,
            tooltip: tooltip,
            style: style,
            onPressed: open,
            icon: icon,
          );
    if (trailingGap == 0) return button;
    return Padding(
      padding: EdgeInsetsDirectional.only(end: trailingGap),
      child: button,
    );
  }
}
