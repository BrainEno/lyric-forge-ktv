# [2026-10-27 17:07] Require reproducible ForcedAligner evaluation provenance

- Scope: Make forced-alignment timing benchmarks auditable by capturing the exact audio fingerprint, manual reference-review status, model revision, and runtime version, with an opt-in gate that refuses incomplete reports without discarding diagnostics.
- Files: `tool/forced_alignment_eval.dart`, `test/tool/forced_alignment_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added tests for complete/legacy provenance reports, strict success/failure, report preservation on failure, capture metadata, and audio changes during alignment.
  - Full Flutter Quality Gate is pending on the PR head; this environment has no local Flutter/Git working tree for direct execution.
- Notes: Capture hashes the bytes before the local alignment request and re-hashes them afterwards to avoid recording metadata for an input that changed in flight. Strict mode validates declared model/runtime identifiers but cannot reconstruct the true version of an old manually assembled corpus.
- Commit: `feat: gate forced-alignment eval on provenance`
