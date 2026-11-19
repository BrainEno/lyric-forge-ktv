# [2026-11-25 10:40] Split the dashboard into section widgets

- Scope: UI/UX audit D-06. `dashboard_screen.dart` held the screen state plus 21 private widgets and helpers in about 1,600 lines, so a change to one card meant scrolling past the hero, the queue and the shelves, and none of them could be tested without pumping the whole dashboard and its services. The screen now keeps its state, data loading, handlers and `_Header` (the contract strings checked by `workflow_screen_injection_contract_test.dart` and `asr_install_experience_contract_test.dart` stay in it); the sections moved to `lib/features/home/presentation/widgets/`. The widgets the screen uses are public (`Dashboard…`), their internals stay private to their file. No behaviour or layout change: the moved code is the same apart from names, `super.key` and line wrapping.
- Files:
  - `lib/features/home/presentation/screens/dashboard_screen.dart` (about 1,600 → 520 lines).
  - `lib/features/home/presentation/widgets/dashboard_surfaces.dart` (new: `DashboardArtwork`, `DashboardEyebrow`, hero/card decorations, muted caption style).
  - `lib/features/home/presentation/widgets/dashboard_now_playing.dart` (new: `DashboardNowPlayingArea` with the idle hero, playing hero, progress, queue card and rows).
  - `lib/features/home/presentation/widgets/dashboard_background_work_card.dart` (new: transcription queue card).
  - `lib/features/home/presentation/widgets/dashboard_shelves.dart` (new: section header, recent shelf, project grid and cards, empty and loading cards, stage labels).
  - `test/features/home/presentation/widgets/dashboard_shelves_test.dart` (new: section header with and without an action on wide and phone widths, empty card with and without a button, project grid labels, taps and phone column, recent shelf taps, loading block height).
- Validation:
  - No Dart/Flutter toolchain in the sandbox. Imports of every new file were checked by script against the symbols each file uses; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - The feature dependency ratchet is unaffected: the new files import only `core/` and domain models; the one cross-feature presentation import (`transcription_config_dialog.dart`) stays in the screen.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The existing dashboard screen tests cover the moved widgets through the screen; the new test covers the shelves directly.
- Commit: `Split the dashboard into section widgets`
