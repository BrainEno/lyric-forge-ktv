# [2027-01-01 10:00] Merge the review filters into one 建议复核 chip

- Scope: round 48, user request: friendlier UI, chosen area 歌词校对：合并成一个“建议复核”筛选 (D-068).
  - Domain: `LyricReviewUrgency { mustCheck, worthCheck }` and `LyricReviewPriority.urgency` (score ≥ `mustCheckScore` 45, the same line as `LyricReviewRiskLevel.high`); `LyricReviewReasonKind` (empty text, timing, engines disagree, low confidence, inserted line, suspicious text — serious first) with `LyricReviewPriorityReason.kind` covering all 26 codes and `LyricReviewPriority.reasonKinds`; `LyricReviewQueue.mustCheckCount`, `worthCheckCount` and `reasonKindCounts` (rows per kind, most common first, ties in enum order).
  - Toolbar: `LyricReviewFilter` is now `{ all, suggested }`; `_FilterMenu` (全部 / 待复核 / 低置信度) became `LyricSuggestedReviewChip` (`chipKey`), an on/off `FilterChip` labelled `建议复核 N` whose tooltip gives the tiers, the three most common reasons and the unscored note; disabled when the queue is empty unless already on; warning-coloured icon while 必看 rows exist. The status line dropped the review count and only shows rows, language and 未评分 N.
  - Rows: the badge says 必看 (warning) or 留意 on every width instead of `优先 N` / `复核`; the tooltip keeps `必看 · 优先级 N` and every reason; semantics read `建议复核，必看`. `LyricReviewRow.warningScore` was removed.
  - Strings: `LyricSuggestedReviewStrings` (chip, urgency, reason kinds, tiers, main reasons, chip / badge tooltips, row semantics). The editor screen's decision snack bars and the queue-done empty state say 建议复核.
  - The list pane's scroll-to-top, follow and resume rules, 循环本行, 开始复核 and the decision jump now key on `LyricReviewFilter.suggested`.
- Files:
  - Changed: `lib/features/lyrics/domain/models/lyric_review_queue.dart`, `lib/features/lyrics/domain/services/lyric_review_priority_service.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/lyrics/presentation/widgets/{lyric_editor_toolbar,lyric_editor_review_controls,lyric_editor_content,lyric_list_pane,lyric_list_states,lyric_review_row,lyric_row_semantics}.dart`.
  - Tests: `test/features/lyrics/domain/models/lyric_review_queue_test.dart`, `test/features/lyrics/domain/services/lyric_review_priority_service_test.dart`, `test/features/lyrics/presentation/lyric_review_strings_test.dart`, `test/features/lyrics/presentation/widgets/{lyric_editor_toolbar,lyric_editor_review_controls,lyric_editor_panes_controls,lyric_list_pane,lyric_review_row,lyric_row_semantics}_test.dart`.
  - `docs/decisions.md` (D-068), `docs/handoff.md`, `docs/lyric_proofreading_ux_review.md` §6 item 13.
- Validation:
  - No Dart SDK in the sandbox; a temporary branch CI probe ran `dart format`, `flutter analyze` and `flutter test`.
  - Probe results: see handoff.
- Notes:
  - The queue still keeps `lowConfidenceIndices` / `lowConfidenceCount` for the review inbox and project screens, which still say 待复核 / 低置信度; aligning them is a follow-up.
  - The editor screen stays at 1198 lines (only strings changed).
- Commit: `Merge the review filters into one suggested-review chip`
