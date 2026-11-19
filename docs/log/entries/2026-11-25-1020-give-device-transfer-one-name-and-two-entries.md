# [2026-11-25 10:20] Give device transfer one name and two entries

- Scope: UI/UX audit L-02. The audit counted four transfer entries for a task done now and then; two were left (the floating button and the player bar menu item went in earlier rounds), but they still disagreed: the library strip said 跨设备传输 with a devices icon, the dashboard header had a desktop-only 远程音乐库 button with a cast icon, and the desktop transfer screen was titled 电脑 ↔ 手机传输. `TransferEntry` (`lib/core/navigation/transfer_entry.dart`) now holds the name, icon and route rule (desktop shares its library at `/media-sharing`, a phone connects at `/remote-library`). The library strip keeps the visible button; the dashboard header drops its own button and lists 跨设备传输 first in its 更多 menu, on phones as well as desktops, so the header is back to 打开音乐, 导入并识别 and 更多. Both transfer screens are titled 跨设备传输.
- Files:
  - `lib/core/navigation/transfer_entry.dart` (new: `TransferEntry.label`, `icon`, `menuValue`, `routeFor`, `open`).
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (header button removed, 更多 menu item, `_isDesktop` gone).
  - `lib/features/player/presentation/screens/local_music_library_shell.dart` (strip button uses `TransferEntry`).
  - `lib/features/transfer/presentation/screens/desktop_media_transfer_hub_screen.dart`, `mobile_media_transfer_hub_screen.dart` (titles).
  - Tests: `test/core/navigation/transfer_entry_test.dart` (new: route per device, name and icon, `open` with and without an explicit device); `test/features/home/presentation/screens/dashboard_screen_test.dart` (no header button on desktop, menu order, phone and desktop routes from 更多).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Phones gain a dashboard entry they did not have (the old header button was desktop-only); it sits in the menu, not on the page.
  - The contract strings checked by `asr_install_experience_contract_test.dart` (更多 tooltip, model settings item) are unchanged.
- Commit: `Give device transfer one name and two entries`
