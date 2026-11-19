# [2026-11-25 10:00] Give each player entry its own route

- Scope: UI/UX audit N-01. Every music entry on the dashboard pushed `/quick-play`, and the router picked a screen from whatever was playing at that moment: the local player, the full-screen now playing view for a desktop Media Hub stream, or the music library. 打开音乐 therefore opened a different page depending on the current song, and because the route name stayed `/quick-play`, the shell kept the mini player bar on top of the now playing view it was meant to hide. The rules now live in `PlaybackDestination` (`lib/core/navigation/playback_destination.dart`), and each dashboard entry pushes the route for its intent: 打开音乐, 选择音乐 and the idle hero open the library (picking something to play); a recent song resumes in the local player with its history entry; the playing hero opens the player that fits the current song (project player, now playing for a stream, local player otherwise). The router resolves a bare `/quick-play` with the same rules, so a deep link lands where a tap would.
- Files:
  - `lib/core/navigation/playback_destination.dart` (new: `PlaybackDestination.resolve` and `routeName`).
  - `lib/app/app_router.dart` (`/quick-play` picks its screen through `PlaybackDestination`).
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (`_openMusic`, `_resumeHistory`, `_openCurrent` replace `_openLocalPlayer`).
  - Tests: `test/core/navigation/playback_destination_test.dart` (new: resolution rules, history first, one route per destination); `test/features/home/presentation/screens/dashboard_screen_test.dart` (routes pushed by 打开音乐, the idle hero, the playing hero for local / stream / project songs, and a recent song with its history entry).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Behaviour change: while a local song plays, 打开音乐 now opens the library instead of the local player for the same song; the playing hero's 打开播放器 is the way to that player. Before, the button and the hero led to the same page.
  - `PlaybackDestination` takes plain values (project id, stream flag) so `core` does not import a feature, and `home` gains no import of another feature's presentation layer.
  - The player bars keep opening `/now-playing`, the source-agnostic full player.
- Commit: `Give each player entry its own route`
