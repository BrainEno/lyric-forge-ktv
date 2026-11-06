# [2026-11-06 01:54] Preserve Korean lyrics across chunk overlaps

- Scope: Fix chunk-result merging so shared multilingual normalization keeps identical Korean overlap lines eligible for deduplication while distinct Korean lyrics are not collapsed because normalization produced an empty string.
- Files: `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`; `test/resumable_chunked_transcription_service_test.dart`; `docs/log/entries/2026-11-06-0154-preserve-korean-chunk-overlap-lines.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42078642488` passed on code head `2cc9638f6a8c368cfa87162a47b89aab9cb2c8af`, including work-log preflight, changed-file formatting, analyze, and the full repository test suite.
  - The first docs-updated PR-head run `42079290302` passed work-log preflight and formatting but failed one unrelated existing Media Hub upload-deadline test (`test/features/transfer/http_media_hub_upload_test.dart`). GitHub refused a rerun with `run cannot be rerun; its workflow file may be broken`; no code in that test or its implementation was changed in this slice. The subsequent PR-head gate `42080009696` passed on `46921fcd5126e1a4ac908dfe33f1189bc5e4c1e9`, including work-log preflight, changed-file formatting, analyze, and the full test suite.
  - Initial formatter check identified the new test block's required wrapping; formatting was corrected in commit `2cc9638` before the passing code-head gate.
  - Local Flutter tests/analyze => not run because Flutter/Dart SDK is unavailable; pinned CI supplied the available results.
- Notes: Independent chunk-merge acceptance slice for issue #317: the regression uses two overlapping Korean chunks, asserts that equal text is merged (higher confidence retained), and asserts that different Korean text survives. PR #356 is open; issue #317 remains open pending its other acceptance criteria. No merge or issue-closure authorization is implied.
- Commit: `fix: preserve Korean lyrics in chunk merges`
