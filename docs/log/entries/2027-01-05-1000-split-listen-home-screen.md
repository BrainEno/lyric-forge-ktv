# [2027-01-05 10:00] Split 听歌 into parts

- Scope: round 52, user request: split the listen home page before it reaches the 1200-line screen budget (D-072). No visible change.
  - `listen_home_screen.dart` (1115 → 493 lines) keeps the state, loading, actions and the order of the sections. The `ListenHomeScreen` statics (`title`, `playAllKey`, `queueFrom`, `titleOf`, `itemFor`, `hasCover`, `distinctRecent`, …) stay; the words and keys now alias `ListenHomeText` / `ListenHomeKeys`.
  - `widgets/listen_home_text.dart`: `ListenHomeText` (words) and `ListenHomeKeys` (keys, plus `recent(historyId)`).
  - `widgets/listen_home_hero.dart`: `ListenHomeHeader`, `ListenHomePlayingHero`, `ListenHomeIdleHero` (moved as they were, made public, given `super.key`).
  - `widgets/listen_home_sections.dart`: `ListenHomeQuickPlayRow`, `ListenHomeLyricsNudge`, `ListenHomeRecentShelf` (new: the 最近播放 rows or the empty line, with `subtitleOf`), `ListenHomeSectionTitle`, `ListenHomeLibraryShortcuts`.
  - `presentation/listen_home_guide.dart`: `ListenHomeGuide` holds the checklist's store and preferences: `load` (first-use decision, never throws), `remember(visibility)` (kept in memory when saving fails) and the pure `progressFrom(entries, overrides, histories)`. The page keeps only the card's state and the undo snackbar.
- Files:
  - New: `lib/features/player/presentation/listen_home_guide.dart`, `lib/features/player/presentation/widgets/{listen_home_text,listen_home_hero,listen_home_sections}.dart`, `test/features/player/presentation/listen_home_guide_test.dart` (8 tests).
  - Changed: `lib/features/player/presentation/screens/listen_home_screen.dart`.
  - `docs/decisions.md` (D-072), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox; a temporary branch CI probe ran `dart format`, `flutter analyze` and `flutter test`.
  - Probe results: see handoff.
- Notes:
  - The existing listen home widget tests are unchanged and act as the regression check for the split.
  - 最近播放 is now one `Column` inside the page's `ListView` instead of one child per row; the rows, keys and padding are the same.
- Commit: `Split the listen home screen into parts`
