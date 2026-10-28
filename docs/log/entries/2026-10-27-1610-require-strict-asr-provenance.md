# [2026-10-27 16:10] Require complete provenance for auditable ASR evaluation

- Scope: Add an opt-in CLI gate that fails auditable transcript benchmarks when input fingerprint, audio duration, manual reference-review status, model revision, or runtime version is absent.
- Files: `tool/asr_transcript_eval.dart`, `test/tool/asr_transcript_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added CLI regression coverage for complete metadata passing strict mode and legacy metadata failing while retaining the report.
  - Flutter Quality Gate run 40477102575 => passed; work-log contract preflight and Dart format passed, and the full suite reported 737 tests passed.
- Notes: Strict mode is opt-in; legacy schema v1 corpora remain evaluable by default and expose provenance warnings. Failure does not erase the diagnostic report.
- Commit: `feat: require provenance for strict ASR evaluation`
