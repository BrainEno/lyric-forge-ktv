# [2026-11-07 13:32] Preserve Latin Extended-D ASR text

- Scope: Keep Latin Extended-D letters in shared lyric tokenization so matching ASR lines are not discarded as empty-normalized text.
- Files: `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-1332-preserve-latin-extended-d-asr.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Unicode 17.0 `Blocks.txt` confirms Latin Extended-D is U+A720–A7FF.
  - Pinned Flutter Quality Gate `42342926141` on code head `f296cf378ee1effd307c34fd562126a1df526f46` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: The tokenizer now retains Latin Extended-D. Comparison tests distinguish U+A723 and U+A725; service coverage checks duplicate-free matching in Qwen-primary and Whisper-primary order. PR #362 and issue #317 remain open; no merge or issue-closure authorization is implied.
- Commit: `fix: preserve Latin Extended-D in ASR matching`
