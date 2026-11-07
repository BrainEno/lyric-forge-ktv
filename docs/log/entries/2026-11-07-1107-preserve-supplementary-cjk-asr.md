# [2026-11-07 11:07] Preserve supplementary CJK ASR text

- Scope: Keep supplementary-plane CJK Unified Ideographs available to ASR line matching instead of dropping them during shared lyric tokenization.
- Files: `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-1107-preserve-supplementary-cjk-asr.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Initial pinned run `42332144479` on `84ceca53cb168c5b5d1467331e5e9d0eade07231` failed the changed-file format check before tests; detailed Actions log retrieval returned EOF.
  - Formatting follow-up `57fae63845a29f4eeeec857271d20a20f17aebbf`; pinned run `42332246659` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: The tokenizer now retains the supplementary CJK Unified Ideograph blocks B–J, including Extension I's non-sequential range, using Unicode 17.0 block boundaries. Unit coverage checks Extension B/J normalization and distinct-text similarity; the service regression checks duplicate-free matching in both engine orders. PR #360 and issue #317 remain open; no merge or issue-closure authorization is implied.
- Commit: `fix: preserve supplementary CJK ideographs`
