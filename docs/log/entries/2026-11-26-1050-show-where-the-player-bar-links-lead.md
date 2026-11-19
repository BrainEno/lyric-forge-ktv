# [2026-11-26 10:50] Show where the player bar links lead

- Scope: Round 9 feedback, second half: once the 音乐库 and 收藏与播放列表 links in the desktop player bar work, they still need to feel like they responded. They were plain grey icon buttons: nothing marked the page the user was on, and pressing the link to that page pushed a second copy of it. Added `AppTapPulse` (a short swell and settle on every press, skipped under reduced motion) and `PlayerBarDestinationButton` / `PlayerBarLinks`. The active link (song, artist and album sections for 音乐库; favourites and playlists for 收藏与播放列表) sits on the deep lavender pill with its filled icon and announces itself as selected. Every press pulses and gives a selection click. Pressing the link to the page already open stays there. The compact bar's menu entries skip the push in the same way.
- Files:
  - `lib/core/widgets/app_tap_pulse.dart` (new).
  - `lib/features/player/presentation/widgets/player_bar_destination_button.dart` (new), `global_player_bar.dart`.
  - `test/core/widgets/app_tap_pulse_test.dart` (new: the scale curve, the pulse on each new trigger, reduced motion).
  - `test/features/player/presentation/widgets/player_bar_destination_button_test.dart` (new: which routes light each link, pill and selected semantics, no push on the open page, the selection click, the highlight following the shell route).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The links follow the route only; switching sections with the chips inside the library does not change the route, so 音乐库 stays lit there.
  - Not checked in a running app.
- Commit: `Show where the player bar links lead`
