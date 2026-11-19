# [2026-11-19 12:25] Offer open music once on the dashboard

- Scope: UI/UX audit C-01. With nothing playing, the dashboard offered the same quick-play route four times: 打开音乐 in the header, 选择音乐开始播放 in the idle hero, 打开音乐 beside 最近播放 and 选择音乐 on the empty history card, which diluted the main action. The idle hero is now the only entry. The header shows 打开音乐 only while something is playing (the hero then shows the current song instead of its button), the 最近播放 header has no action, and the empty history card keeps its button only while something is playing. `_SectionHeader` and `_EmptyCard` take an optional action; 最近工程 keeps 批量导入.
- Files:
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (`_Header.showOpenMusic`, optional `_SectionHeader` and `_EmptyCard` actions).
  - Test: `test/features/home/presentation/screens/dashboard_screen_test.dart` (the fake session takes a state; nothing playing leaves only the hero button; while playing the header button appears and the idle hero is gone).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Pull-to-refresh, retry buttons and the 远程音乐库 / 导入并识别 / 更多 header actions are unchanged.
- Commit: `Offer open music once on the dashboard`
