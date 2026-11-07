# [2026-11-07 12:55] Preserve Cyrillic extension ASR text

- Scope: Keep Cyrillic Supplement and Extended letters, plus Cyrillic combining marks, available to ASR line matching instead of dropping them during shared lyric tokenization.
- Files: `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-1255-preserve-cyrillic-extended-asr.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Unicode 17.0 `Blocks.txt` boundaries for Cyrillic Supplement/Extended ranges verified from `unicode-org/unicodetools`.
  - Pinned Flutter Quality Gate `42340288906` on code head `4fb9b8b3981a146c005a7cd3c656bcb1c321b88e` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: Coverage includes U+0500–052F, U+1C80–1C8F, Cyrillic combining marks U+2DE0–2DFF, U+A640–A69F, and U+1E030–1E08F. Comparison tests verify each range is retained; service tests ensure matching lines are deduplicated in Qwen-primary and Whisper-primary order. PR #361 and issue #317 remain open; no merge or issue-closure authorization is implied.
- Commit: `fix: preserve Cyrillic extensions in ASR matching`
