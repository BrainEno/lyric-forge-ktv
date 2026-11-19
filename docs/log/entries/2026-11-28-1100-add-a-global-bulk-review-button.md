# [2026-11-28 11:00] Add a global bulk review button

- Scope: Audit R-03, second half (user request: 全局的批量复核按钮). The inbox could only mark one project reviewed at a time from its 更多操作 menu. The summary line is now `ReviewInboxSummaryBar`, which adds a 全部工程标为已复核 button while any project still waits. A confirmation (`ReviewInboxGlobalReviewDialog`) says how many projects and lines it changes, names the first three projects and notes that later edits put a line back in the queue. While it runs the button becomes a live-region progress line ("正在标记第 N/M 个工程…") with a determinate bar, and the per-project menus are disabled. `ReviewInboxBulkReview.markAllProjectsReviewed` saves one project at a time with the editor's revision check: a project saved elsewhere since the inbox read it is skipped as a conflict, a failing save is counted and does not stop the rest, and nothing throws. The result snackbar reports saved, skipped and failed projects, and 撤销 restores every saved project that has not been saved again since (`undoBatch`).
- Files:
  - `lib/features/lyrics/presentation/controllers/review_inbox_bulk_review.dart` (`markAllProjectsReviewed`, `undoBatch`, `BulkReviewBatchResult`, `BulkReviewBatchUndo`).
  - `lib/features/lyrics/presentation/widgets/review_inbox_global_review.dart` (new: text, summary bar, confirmation).
  - `lib/features/lyrics/presentation/screens/review_inbox_screen.dart`.
  - `test/features/lyrics/presentation/controllers/review_inbox_batch_review_test.dart` (new: progress, conflicts, failures, unchanged, undo paths).
  - `test/features/lyrics/presentation/widgets/review_inbox_global_review_test.dart` (new: sentences, button and progress states, confirmation).
  - `test/features/lyrics/presentation/screens/review_inbox_screen_test.dart` (button visibility, confirmation text, cancel, mark and undo, conflict skip, progress with disabled menus).
  - `artifacts/ui-audit/reports/issues.md`, `artifacts/ui-audit/reports/pages/review-inbox-and-transfer.md` (R-03 done).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Projects are saved one after another rather than in parallel: the file store serialises writes anyway, and sequential saves give honest progress.
- Commit: `Add a global bulk review button`
