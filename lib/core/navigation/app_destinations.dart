import 'package:flutter/material.dart';

import 'app_router.dart';

/// The four places the app can be, as far as the user is concerned.
///
/// Before this existed the app was three disconnected worlds wired together by
/// buttons on the dashboard: the music library, the KTV/proofreading flow, and
/// device transfer. There was no persistent way to say "take me back", so the
/// only route home was the back stack — which by then could be six screens deep
/// and, after an import, was simply wrong.
///
/// Device transfer did not become a destination: it is something you do from
/// inside the library, not a place you live. It stays reachable from both the
/// library shell and the dashboard header.
enum AppDestination {
  projects,
  library,
  review,
  settings,
}

extension AppDestinationX on AppDestination {
  String get label => switch (this) {
    AppDestination.projects => '工程',
    AppDestination.library => '音乐库',
    AppDestination.review => '校对',
    AppDestination.settings => '设置',
  };

  IconData get icon => switch (this) {
    AppDestination.projects => Icons.library_books_outlined,
    AppDestination.library => Icons.library_music_outlined,
    AppDestination.review => Icons.spellcheck_rounded,
    AppDestination.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppDestination.projects => Icons.library_books_rounded,
    AppDestination.library => Icons.library_music_rounded,
    AppDestination.review => Icons.fact_check_rounded,
    AppDestination.settings => Icons.settings_rounded,
  };

  /// Route to open when the destination is chosen.
  String get route => switch (this) {
    AppDestination.projects => Routes.home,
    AppDestination.library => Routes.library,
    AppDestination.review => Routes.review,
    AppDestination.settings => Routes.settings,
  };

  /// One-sentence explanation for tooltips and accessibility labels.
  String get description => switch (this) {
    AppDestination.projects => '导入歌曲、继续识别、打开工程',
    AppDestination.library => '本机的歌曲、艺人、专辑与歌单',
    AppDestination.review => '挑选需要校对的歌词',
    AppDestination.settings => '播放、识别与存储设置',
  };
}

/// Which destination a route belongs to, for highlighting the right entry.
///
/// Returns null for routes that belong to none — device transfer, the
/// full-screen player, and the immersive KTV view. Those screens hide the
/// navigation entirely, so "nothing is selected" never reaches the user.
AppDestination? destinationForRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return null;
  final path = Uri.parse(routeName).path;

  if (path == Routes.review) return AppDestination.review;
  if (path == Routes.settings) return AppDestination.settings;

  if (path == Routes.library ||
      path.startsWith('${Routes.library}/') ||
      path == Routes.collections ||
      path == Routes.playlists ||
      path == Routes.quickPlay ||
      path == Routes.nowPlaying) {
    return AppDestination.library;
  }

  if (path == Routes.home || path == Routes.dashboard || path == Routes.import) {
    return AppDestination.projects;
  }

  // `/project/:id` is a project; `/project/:id/lyrics` is where proofreading
  // happens, so it highlights 校对 instead.
  if (path.startsWith('/project/')) {
    return path.endsWith('/lyrics')
        ? AppDestination.review
        : AppDestination.projects;
  }

  return null;
}
