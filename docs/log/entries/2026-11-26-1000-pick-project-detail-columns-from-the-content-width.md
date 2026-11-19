# [2026-11-26 10:00] Pick project detail columns from the content width

- Scope: UI/UX audit P-03 (P3). The audit suspected a single long column on wide screens. The page already had two columns, but it picked them from the window width (`supportsTwoPane`, 1080 px+) inside a `LayoutBuilder` whose constraints it ignored. With the app shell's rail and the page gutters, a 1100 px window squeezed the side panel and the lyric cards into about 950 px, and the side panel had a fixed 340/390/420 px width. The new `ProjectDetailColumns` decides from the width it is actually given. It uses two columns from 880 px of content, with the side column about a third of the row (320–440 px) and the lyric cards taking the rest. Below 880 px it stacks with the actions first, as before.
- Files:
  - `lib/features/project/presentation/widgets/project_detail_columns.dart` (new).
  - `lib/features/project/presentation/screens/project_detail_screen.dart` (`_ProjectDetailContent` hands its two columns to it).
  - `test/features/project/presentation/widgets/project_detail_columns_test.dart` (new: threshold, side width bounds, stacked order and gap, side-by-side geometry, a wide window with a narrow content area).
- Validation:
  - `test/features/project/presentation/project_detail_capability_test.dart` (actions reachable at several sizes and text scales) is unchanged.
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The hero stays full width above both columns.
  - Not checked in a running app.
- Commit: `Pick project detail columns from the content width`
