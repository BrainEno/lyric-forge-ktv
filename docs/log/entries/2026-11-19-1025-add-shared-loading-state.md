# [2026-11-19 10:25] Add a shared loading state for pages and panes

- Scope: UI/UX audit, loading states (Phase 2, follows the shared error state). Pages and panes showed a bare `Center(child: CircularProgressIndicator())` with no accessible label and no hint of what was loading. `AppLoadingState` in `lib/core/widgets/` centres the theme spinner with a spoken label ("正在加载" by default) and an optional secondary line of text that also becomes the label. Its 16 px padding keeps it inside short panes.
- Files:
  - `lib/core/widgets/app_loading_state.dart` (new) and `test/core/widgets/app_loading_state_test.dart` (new: default label, message below the spinner, short pane).
  - Migrated: `review_inbox_screen.dart` ("正在读取歌词工程"), `player_screen.dart` ("正在准备播放器"), `project_detail_screen.dart` ("正在读取工程"), and the label-only spinners of `local_collections_screen.dart`, `local_library_explorer_screen.dart` and `local_artist_album_browser_screen.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Lines were measured for the tall-style formatter. Existing tests were searched for spinner lookups on these screens; none depend on them.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: the review inbox, project player and project detail show a short line under the spinner while they load; the library screens look the same but their spinner now has a spoken label.
  - Not migrated: the lyric editor's loading scaffold and spinners inside buttons, list footers, sheets and dialogs (quick play, metadata dialog, take history, transfer screens); those are inline progress indicators rather than page states.
- Commit: `Add a shared loading state for pages and panes`
