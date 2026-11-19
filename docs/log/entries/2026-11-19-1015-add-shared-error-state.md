# [2026-11-19 10:15] Add a shared error state for failed loads

- Scope: UI/UX audit, error states (Phase 2). The lyric editor, project player, project detail and artist/album browser each drew their own load-failure view: red icons of 52, 56 or 64 px, a title with or without an explanation, and retry buttons that were filled, tonal or outlined, labelled "重试" or "重新加载", some at 40 px height. `AppErrorState` in `lib/core/widgets/` reuses the `AppEmptyState` layout with a red icon, adds an optional retry button (tonal, refresh icon, 48 px minimum height, label defaults to "重试") and wraps the text in a live region so screen readers announce the failure. `AppEmptyState` gains an optional `iconColor` for this (additive; the default stays `textTertiary`).
- Files:
  - `lib/core/widgets/app_error_state.dart` (new), `lib/core/widgets/app_empty_state.dart` (`iconColor`), `test/core/widgets/app_error_state_test.dart` (new: text, red icon, retry, touch height, no-retry panel, live region, empty-state default colour).
  - Migrated: `lyric_editor_content.dart` (`LyricEditorErrorState`, keeps its app bar), `player_screen.dart` and `project_detail_screen.dart` (`_ErrorState`), `local_artist_album_browser_screen.dart` (`_CatalogError`; the stored error is now the raw error text, shown under the title "媒体分类加载失败" instead of being prefixed with it).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Lines were measured for the tall-style formatter (two 80-column lines are joined the way the formatter joins them). Existing tests were searched for the old error texts and retry buttons; the dashboard and review inbox keep their own retry buttons, which their tests look up, and were not touched.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: all four failures show a 56 px red icon, a bold title, a secondary explanation and a tonal "重试" button (project detail keeps "重新加载"). The lyric editor and project player gain an explanation line; the artist/album browser's retry button changes from outlined to tonal.
  - Loading spinners are unchanged here; a shared loading view is the next slice.
- Commit: `Add a shared error state for failed loads`
