# [2026-11-25 12:30] Mark a whole project reviewed from the inbox

- Scope: UI/UX audit R-03 ("无批量操作（如全部标为已复核），需逐工程进入"). Confirming a song meant opening it in the editor and marking the queued lines one by one, even after checking it elsewhere. Every review inbox row that still has queued lines now has a 更多操作 menu with 全部标为已复核. A confirmation dialog states how many lines become confirmed and how many leave the queue, and that editing a line later puts it back. The save uses the editor's own fingerprinted decisions and the same revision check as the editor (`updateProjectIfUnchanged`), so a newer save is never overwritten: a conflict writes nothing and asks the user to try again. A SnackBar offers 撤销, which restores the previous lyrics under the same check. The row shows a spinner while its save runs, and the other menus are disabled meanwhile.
- Files:
  - `lib/features/lyrics/domain/services/lyric_review_decision_service.dart` (`setAllReviewed`: one pass, keeps the timestamps of still-valid decisions, drops stale ones, skips lines without IDs, returns the same document when nothing changes).
  - `lib/features/lyrics/presentation/controllers/review_inbox_bulk_review.dart` (new: `ReviewInboxBulkReview`, `BulkReviewResult`, `BulkReviewStatus`; assigns missing line IDs first, as the editor does on open).
  - `lib/features/lyrics/presentation/screens/review_inbox_screen.dart` (row menu, dialog, SnackBars, undo, reload).
  - `test/features/lyrics/domain/services/lyric_review_decision_bulk_test.dart` (new, 8 tests).
  - `test/features/lyrics/presentation/controllers/review_inbox_bulk_review_test.dart` (new, 8 tests: save with the revision check, IDs for old documents, conflict, nothing to do, other errors, undo, undo conflict, undo without a save).
  - `test/features/lyrics/presentation/screens/review_inbox_screen_test.dart` (the fake repository now enforces revisions; 5 new tests: menu only on pending rows, dialog numbers, cancel, confirm then undo, conflict).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Decision: the action is per project, not one button for the whole inbox. Confirming every project at once would empty the queue without anyone looking at it; one project at a time keeps the decision tied to a song the user has checked.
  - The existing `lyric_review_decision_service_test.dart` predates the current formatter, so the bulk tests live in a new file instead of growing it.
- Commit: `Mark a whole project reviewed from the inbox`
