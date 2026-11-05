# [2026-11-05 21:50] Cover distinct Korean ASR hypotheses

- Scope: Verify that different Korean transcripts for the same timed segment remain reviewable as a dual-engine disagreement, without replacing the authoritative lyric or creating a secondary-only duplicate, in both engine orders.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-05-2150-cover-distinct-korean-asr-hypotheses.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - `flutter test test/high_quality_transcription_service_test.dart` => not run locally because Flutter/Dart SDK is unavailable; pinned CI pending.
- Notes: This is one independently testable acceptance slice for issue #317. It checks conflicting Korean hypotheses and visible candidate evidence in both engine orders; secondary-only Korean lyrics and chunk-merge paths remain separate follow-up slices. No PR merge or issue closure is authorized.
- Commit: `test: cover distinct Korean ASR hypotheses`
