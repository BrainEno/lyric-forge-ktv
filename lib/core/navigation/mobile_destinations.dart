import 'package:flutter/material.dart';

import 'app_destinations.dart';
import 'destination_navigation.dart';
import 'routes.dart';

/// The four places of the phone app (decision D-041).
///
/// The phone is first of all an offline player that can also bring in
/// lyrics, but it used to open on the desktop's 工程 dashboard — recognition
/// queues, project grids and model settings — with listening one tab away.
/// The phone now has its own bar:
///
///  * 听歌 — what is playing, recent plays and play-all, and the app opens
///    here;
///  * 音乐库 — the songs, artists, albums, favourites and playlists;
///  * 歌词 — giving the songs lyrics: online, from a lyric file or pasted
///    text, and swapping songs and lyrics with the computer. A phone cannot
///    run recognition, so there are no projects or review here (D-058);
///  * 设置.
///
/// The desktop keeps [AppDestination], where projects are the work.
enum MobileDestination { listen, library, lyrics, settings }

extension MobileDestinationX on MobileDestination {
  String get label => switch (this) {
    MobileDestination.listen => '听歌',
    MobileDestination.library => '音乐库',
    MobileDestination.lyrics => '歌词',
    MobileDestination.settings => '设置',
  };

  IconData get icon => switch (this) {
    MobileDestination.listen => Icons.album_outlined,
    MobileDestination.library => Icons.library_music_outlined,
    MobileDestination.lyrics => Icons.lyrics_outlined,
    MobileDestination.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    MobileDestination.listen => Icons.album_rounded,
    MobileDestination.library => Icons.library_music_rounded,
    MobileDestination.lyrics => Icons.lyrics_rounded,
    MobileDestination.settings => Icons.settings_rounded,
  };

  /// Route to open when the destination is chosen.
  String get route => switch (this) {
    MobileDestination.listen => Routes.home,
    MobileDestination.library => Routes.library,
    MobileDestination.lyrics => Routes.review,
    MobileDestination.settings => Routes.settings,
  };

  /// One-sentence explanation for tooltips and accessibility labels.
  String get description => switch (this) {
    MobileDestination.listen => '正在播放、最近播放与随机播放',
    MobileDestination.library => '本机的歌曲、艺人、专辑与歌单',
    MobileDestination.lyrics => '给歌曲配歌词，与电脑互传歌曲和歌词',
    MobileDestination.settings => '外观主题、曲库目录与诊断',
  };
}

/// Which phone destination a route belongs to, for highlighting the bar.
///
/// The root route is the listening home. Everything the desktop files under
/// 工程 (the dashboard, import, a project) or 校对 (the inbox, the editor)
/// is lyric work on the phone. Routes outside every destination, such as
/// device transfer, return null, and the bar hides there.
MobileDestination? mobileDestinationForRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return null;
  if (Uri.parse(routeName).path == Routes.home) {
    return MobileDestination.listen;
  }
  return switch (destinationForRoute(routeName)) {
    AppDestination.projects ||
    AppDestination.review => MobileDestination.lyrics,
    AppDestination.library => MobileDestination.library,
    AppDestination.settings => MobileDestination.settings,
    null => null,
  };
}

/// Decides what a press on [destination] does while [currentRoute] is shown;
/// see [planDestinationTap] for the desktop rules this mirrors.
DestinationTap planMobileDestinationTap(
  MobileDestination destination,
  String? currentRoute,
) {
  if (currentRoute == null || currentRoute.isEmpty) return DestinationTap.open;
  return Uri.parse(currentRoute).path == destination.route
      ? DestinationTap.stay
      : DestinationTap.open;
}

/// Sends the user to [destination] from anywhere on the phone.
///
/// 「听歌」 is the root route, so it pops back to it; the other three are
/// pushed on top of it, so that one press of back returns to listening
/// rather than leaving the app. Returns what it did.
DestinationTap goToMobileDestination(
  NavigatorState navigator,
  MobileDestination destination,
  String? currentRoute,
) {
  final plan = planMobileDestinationTap(destination, currentRoute);
  if (plan == DestinationTap.stay) return plan;
  if (destination == MobileDestination.listen) {
    navigator.popUntil((route) => route.isFirst);
  } else {
    navigator.pushNamedAndRemoveUntil(
      destination.route,
      (route) => route.isFirst,
    );
  }
  return plan;
}
