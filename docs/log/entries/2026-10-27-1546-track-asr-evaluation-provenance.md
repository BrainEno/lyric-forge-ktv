# [2026-10-27 15:46] Track provenance for paired ASR evaluation

- Scope: Make transcript benchmark inputs auditable by recording exact audio fingerprints, duration, explicit reference-review status, and model/runtime revisions while preserving compatibility with existing schema v1 corpora.
- Files: `tool/asr_transcript_eval.dart`, `test/tool/asr_transcript_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - GitHub Actions Flutter Quality Gate run 40470097830 => passed; work-log contract preflight and changed-file Dart formatting passed, and the full suite reported 736 tests passed.
- Notes: Provenance metadata does not validate the audio or reference by itself; human review remains necessary. Existing schema v1 corpora remain accepted and are annotated with completeness warnings.
- Commit: `feat: track ASR evaluation input provenance`
