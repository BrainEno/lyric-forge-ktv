# [2027-01-02 10:00] Use the editor's 建议复核 · 必看 wording on every review surface

- Scope: round 49, user request: friendlier UI, chosen area 统一“建议复核”说法 (D-069), following D-068.
  - Review inbox: tiles show `建议复核 N` (neutral) and `必看 M` (warning), or `未评分 N` when nothing is 必看; a `主要原因：…` line under the subtitle (`review-inbox:reasons:<id>`); sorted by 必看, then 建议复核, then recency; the summary line is `ReviewInboxScreen.summaryLine` (`N 个工程，共 M 行建议复核，其中 K 行必看`); `tileLabel` takes `mustCheck` and `reasons` instead of `lowConfidence`; the mark-all dialog and the inbox-wide note use 建议复核 / 移出列表 / 重新列入建议复核.
  - Project detail: `ProjectLyricReviewOverview` and `ProjectLyricReviewCounter` in the project domain; `ProjectDetailDependencies.reviewCounter`, assembled as `countProjectLyricReview` in `lib/app/screen_assembly.dart` (builds `LyricReviewQueue` with the audio length); the lyric card shows `建议复核 · N 行 / 无` and `必看 · M 行` with a matching sentence, and no longer shows the `lowConfidenceLineCount` / `fallbackCandidateCount` metadata frozen at recognition time.
  - Recognition summary: `RecognitionReviewSummary.mustCheckReview`; the metric reads `建议复核：N（必看 M）` via `LyricSuggestedReviewStrings.countWithMustCheck` / `mustCheckLabel`; gap-fill text says 列入建议复核.
  - Wording: inspector badge `置信度低 N`; config dialog `第二引擎复查阈值` with an explanation; profile description and recognition log messages say 列入建议复核. Reference-alignment 低置信 / 歧义 (alignment confidence) is unchanged.
- Files:
  - New: `lib/features/project/domain/models/lyric_review_overview.dart`, `test/app/project_review_counter_test.dart`.
  - Changed: `lib/app/screen_assembly.dart`, `lib/features/lyrics/domain/models/recognition_review_summary.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/screens/review_inbox_screen.dart`, `lib/features/lyrics/presentation/widgets/{review_inbox_global_review,lyric_recognition_summary_card,lyric_inspector_pane}.dart`, `lib/features/project/presentation/{project_detail_dependencies,screens/project_detail_screen}.dart`, `lib/features/transcription/data/services/{high_quality_transcription_service,native_transcription_profile_resolver}.dart`, `lib/features/transcription/presentation/widgets/transcription_config_dialog.dart`.
  - Tests: `test/features/lyrics/presentation/screens/review_inbox_screen_test.dart`, `test/features/lyrics/presentation/widgets/{review_inbox_global_review_test,lyric_recognition_gap_fill_test}.dart`, `test/features/lyrics/presentation/{lyric_review_strings_test,secondary_suggestion_review_flow_test}.dart`, `test/features/project/presentation/project_detail_capability_test.dart`.
  - `docs/decisions.md` (D-069), `docs/handoff.md`, `docs/lyric_proofreading_ux_review.md` §6 item 13.
- Validation:
  - No Dart SDK in the sandbox; a temporary branch CI probe ran `dart format`, `flutter analyze` and `flutter test`.
  - Probe results: see handoff.
- Notes:
  - The project feature still does not import the lyrics feature; the counter is injected from `lib/app`, so the feature dependency graph is unchanged.
  - `LyricReviewQueue.lowConfidenceCount` is no longer shown anywhere but kept for the queue's own tests and future use.
- Commit: `Use the suggested-review wording on every review surface`
