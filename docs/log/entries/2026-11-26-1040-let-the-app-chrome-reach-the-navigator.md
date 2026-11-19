# [2026-11-26 10:40] Let the app chrome reach the navigator

- Scope: Round 9 feedback: the 音乐库 and 收藏与播放列表 buttons at the bottom gave no feedback. They did nothing at all. The player bars, the transcription queue bar and the persistent navigation are built in `MaterialApp.builder`, beside the navigator rather than under it, so `Navigator.pushNamed(context, …)`, `showDialog` and the `PopupMenuButton` in the desktop bar threw "context does not include a Navigator", and the gesture handler swallowed the error. Separately, the desktop chrome was `Overlay(initialEntries: [OverlayEntry(builder: …)])` rebuilt from the route listener. An overlay reads its initial entries once, so the entry kept the closure of the first frame: the rail stayed on 工程 and the player bar stayed up on the full player. Added `AppChromeScope` (navigator key + current route, with `navigatorOf`, `contextOf`, `pushNamed`, falling back to the nearest navigator) and `AppChrome` (the chrome layout, with one long-lived overlay entry that listens to the route itself). The player bars, the queue bar and the queue panel's save-as-playlist dialog go through the scope. The compact bar's overflow menu is now a `MenuAnchor`, which needs only the overlay. `goToDestination` / `planDestinationTap` replace the inline routing in `app.dart`: pressing the destination already on screen no longer pushes it again.
- Files:
  - `lib/core/navigation/app_chrome_scope.dart`, `lib/core/navigation/destination_navigation.dart` (new).
  - `lib/app/app_chrome.dart` (new), `lib/app/app.dart`.
  - `lib/features/player/presentation/widgets/global_player_bar.dart`, `mobile_global_player_bar.dart`, `playback_queue_panel.dart`.
  - `lib/features/transcription/presentation/widgets/global_transcription_queue_bar.dart`.
  - `test/widget_test.dart` (the mobile shell now has the chrome overlay).
  - `test/app/app_chrome_test.dart` (new: the production arrangement with the chrome in `MaterialApp.builder`; the rail and bottom bar follow the route, the bar pushes routes and opens dialogs, it steps aside on the full player, and re-pressing a destination keeps the page).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The mobile chrome shares the overlay host: without one the bottom bar's destination tooltips threw "No Overlay widget found" on this Flutter version (the CI probe caught it in `app_chrome_test`). `test/widget_test.dart` used to pin the mobile chrome as overlay-free and now expects the chrome overlay.
  - Not checked in a running app.
- Commit: `Let the app chrome reach the navigator`
