# [2026-11-07 12:45] Preserve Greek Extended ASR text

- Scope: Keep polytonic Greek Extended letters in shared lyric tokenization so matching ASR lines are not discarded as empty-normalized text.
- Files: `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`; `test/asr_text_comparison_test.dart`; `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-1245-preserve-greek-extended-asr.md`; generated work-log navigation; `docs/work_log_index.md`; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate `42339604592` on code head `1a9f1e5149fc5161a274f7e4120f284150e387fd` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: `LyricTokenizer` now retains Greek Extended U+1F00–U+1FFF. Comparison tests use distinct polytonic Greek letters; a service-level test verifies a matching Greek Extended lyric is deduplicated in both Qwen-primary and Whisper-primary orders. PR #361 is open; issue #317 remains open. No merge or issue-closure authorization is implied.
- Commit: `fix: preserve polytonic Greek in ASR matching`
