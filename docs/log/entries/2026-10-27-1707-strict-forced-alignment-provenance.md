# [2026-10-27 17:07] Require reproducible ForcedAligner evaluation provenance

- Scope: Make forced-alignment timing benchmarks auditable by capturing the exact audio fingerprint, manual reference-review status, model revision, and runtime version, with an opt-in gate that refuses incomplete reports without discarding diagnostics.
- Files: `tool/forced_alignment_eval.dart`, `test/tool/forced_alignment_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Flutter Quality Gate run 40480645675 on implementation head `0ec5ccd994953561b9ba6ac92039bef952a711ed` passed: work-log preflight, changed-Dart format check, repository quality gate, and all 741 tests.
  - A documentation-only follow-up changes the PR head; recheck that newer head's workflow before merge.
- Notes: Capture hashes the bytes before the local alignment request and re-hashes them afterwards to avoid recording metadata for an input that changed in flight. Strict mode validates declared model/runtime identifiers but cannot reconstruct the true version of an old manually assembled corpus.
- Commit: `feat: gate forced-alignment eval on provenance`
