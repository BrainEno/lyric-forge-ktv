# [2026-11-19 12:10] Fold reviewed projects in the review inbox

- Scope: UI/UX audit R-01 and R-02. The review inbox showed every project with the same lyric icon tile and kept fully reviewed projects in the same list as the ones still waiting, so it grew with finished work. Rows now show the song's cover through `AppArtwork` (lyric icon placeholder when there is none). While anything is waiting, reviewed projects are folded behind 已复核的工程 · N 个 (48 dp toggle, announced as an expandable button); when everything is reviewed they are the list. The private `_Message` widget gave way to `AppErrorState` and `AppEmptyState`.
- Files:
  - `lib/features/lyrics/presentation/screens/review_inbox_screen.dart` (`ReviewInboxEntry.isFullyReviewed`, `_rows`, `_ReviewedToggle`, cover artwork, shared error/empty states).
  - Test: `test/features/lyrics/presentation/screens/review_inbox_screen_test.dart` (the ordering test expands the folded group first; new cases: all reviewed shows the list without a toggle, collapse hides the group again, the row uses `AppArtwork` with the lyric placeholder).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Copy of the empty, error and summary lines and the retry and 去导入 actions is unchanged.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The fold state lives in the screen and resets when the inbox is reopened, so new review work is always on top.
  - Cover comes from `audioAsset.thumbnailPath`, the same field the dashboard and player use.
- Commit: `Fold reviewed projects in the review inbox`
