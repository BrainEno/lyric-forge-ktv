# [2026-11-29 11:00] Tidy reorder callbacks and pending colours

- Scope: Two leftovers from the round 11 handoff. The playlist and play-queue lists used `ReorderableListView.onReorder`, deprecated after Flutter 3.41 in favour of `onReorderItem`, which already adjusts the target index for the removed row; both now use `onReorderItem` and drop their own adjustment. The review inbox showed 待复核 in the lavender accent and the reference alignment review showed 待确认 the same way, while the editor's status line uses the warning colour for lines that still need a look (audit E-03); both now use `AppColors.warning`, and lavender stays for things to press.
- Files:
  - `lib/features/player/presentation/screens/local_collections_screen.dart`, `lib/features/player/presentation/widgets/playback_queue_panel.dart`.
  - `lib/features/lyrics/presentation/screens/review_inbox_screen.dart`, `lib/features/lyrics/presentation/widgets/reference_alignment_review.dart`.
  - `artifacts/ui-audit/reports/issues.md` (E-03 note).
- Validation:
  - Checked the callback contract against Flutter 3.47.7's `packages/flutter/lib/src/widgets/reorderable_list.dart` (`onReorderItem` is called with `newIndex` already reduced when moving down, and only when the index changes).
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - In the inbox, 待复核 and 低置信度 now share the warning colour; their labels tell them apart, as in the editor.
  - Not tried in a running app.
- Commit: `Tidy reorder callbacks and pending colours`
