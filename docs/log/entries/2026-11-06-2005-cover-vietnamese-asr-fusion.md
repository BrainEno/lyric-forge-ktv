# [2026-11-06 20:05] Cover Vietnamese diacritics in ASR fusion

- Scope: Add an end-to-end dual-engine regression for Vietnamese extended-Latin diacritics so composed Vietnamese text and its unaccented ASR spelling match in either primary-engine order.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-06-2005-cover-vietnamese-asr-fusion.md`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate `42214638985` on code head `d0302e49873f005e470fb8c131361df852595886` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: The existing multilingual service regression now pairs Qwen `Tiếng Việt` with Whisper `Tieng Viet`; it asserts the primary rows remain unchanged, with no duplicate secondary-only rows or disagreement candidates in both Qwen-primary and Whisper-primary order. PR #359 is open and relates to issue #317. The documentation/handoff commit still needs its own final-head gate; do not merge PR #359 without user authorization. Issue #317 remains open.
- Commit: `test: cover Vietnamese ASR fusion normalization`
