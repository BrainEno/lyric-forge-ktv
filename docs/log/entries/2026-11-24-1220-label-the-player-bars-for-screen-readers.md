# [2026-11-24 12:20] Label the player bars for screen readers

- Scope: UI/UX audit A-04 (Semantics on core controls), starting with the player bars, which are on screen almost all the time. A screen reader met an unlabelled artwork button on the desktop bar, a queue toggle that only said "3" on compact widths, and a play button that kept saying 播放 while it was disabled during loading; on mobile, the whole bar was one tap target mixed with its own buttons. Both bars now read the title block as one button, 正在播放：<title>，<subtitle> with the hint 打开播放页 (the desktop artwork is excluded as a duplicate of the same destination; on mobile the bar-wide InkWell is excluded from semantics so the skip and play buttons keep their own nodes). The play button says 正在加载 while buffering or loading, the same word as the full player's `TransportBar`, and the desktop bar now also locks it during loading like the mobile bar. The queue toggle has a 播放队列 tooltip and reads 播放队列，N 首 with its expanded state. The library search clear button gets the missing 清除搜索 tooltip.
- Files:
  - `lib/features/player/presentation/widgets/player_bar_semantics.dart` (new: `PlayerBarSemantics` labels, `PlayerBarNowPlayingTarget`, `PlayerBarQueueToggle`).
  - `lib/features/player/presentation/widgets/global_player_bar.dart` (subtitle via `subtitleFor`, one `openNowPlaying`, labelled title block, artwork excluded, busy label and lock, queue toggle).
  - `lib/features/player/presentation/widgets/mobile_global_player_bar.dart` (labelled title block, `_TitleBlock`, busy label).
  - `lib/features/player/presentation/screens/local_library_explorer_screen.dart` (clear-search tooltip).
  - Test: `test/features/player/presentation/widgets/player_bar_semantics_test.dart` (new: label functions; mobile bar reads one button and opens `/now-playing`, buffering label, no bar without a song; desktop bar reads the title once, queue toggle label and expanded state at compact width, buffering label with the shortcut hint).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible text, layout and routes are unchanged. On mobile a project song without an artist still shows 本地音乐, and a remote one 桌面音乐库.
  - A scan for `IconButton` without a tooltip found no other unlabelled icon buttons in `lib/`.
- Commit: `Label the player bars for screen readers`
