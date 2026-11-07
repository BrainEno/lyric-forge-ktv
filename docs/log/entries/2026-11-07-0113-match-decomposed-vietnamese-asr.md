# [2026-11-07 01:13] Match decomposed Vietnamese ASR output

- Scope: Verify dual-engine fusion treats precomposed Vietnamese and canonically decomposed Vietnamese as the same lyric, regardless of which engine is primary.
- Files: `test/high_quality_transcription_service_test.dart`; `docs/log/entries/2026-11-07-0113-match-decomposed-vietnamese-asr.md`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - First pinned run `42258479008` on initial code head `5294d3ffe53864d0fa1da983bc662d36de61b289` failed the changed-file format check before tests ran; detailed Actions logs were unavailable (EOF).
  - Follow-up pinned run `42259148984` on code head `b81a30c380d99923e58479a81f5851565e3ecacd` => work-log preflight, changed-file formatting, and repository quality gate all passed.
  - Local Flutter/Dart tests/analyze => not run because Flutter/Dart SDK is unavailable.
- Notes: The regression pairs Qwen `Tiếng Việt` with Whisper `Tie\u0302\u0301ng Vie\u0323\u0302t`, in both engine orders, and asserts exactly one primary row with no secondary-only row or disagreement candidate. PR #360 is open; do not merge without user authorization. Issue #317 remains open.
- Commit: `test: simplify decomposed Vietnamese fusion assertions`
