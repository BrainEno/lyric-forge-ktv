# [2026-11-07 14:25] Preserve Latin Extended-C ASR text

- Scope: Keep Latin Extended-C letters in shared lyric tokenization so matching ASR lines are not discarded as empty-normalized text.
- Files: `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-1425-preserve-latin-extended-c-asr.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Unicode 17.0 `Blocks.txt` confirms Latin Extended-C is U+2C60–2C7F.
  - Pinned Flutter Quality Gate `42346730040` on code head `7e48575ebd4b4a0e178a8b8a6f6fb93e75d2551a` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: The tokenizer now retains Latin Extended-C. Comparison tests distinguish U+2C65 and U+2C66; service coverage checks duplicate-free matching in Qwen-primary and Whisper-primary order. PR #363 and issue #317 remain open; no merge or issue-closure authorization is implied.
- Commit: `fix: preserve Latin Extended-C in ASR matching`
