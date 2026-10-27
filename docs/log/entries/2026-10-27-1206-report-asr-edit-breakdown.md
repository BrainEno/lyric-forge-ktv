# [2026-10-27 12:06] Report ASR insertions, omissions, and substitutions

- Scope: Extend paired ASR transcript evaluation with an explainable edit-operation breakdown so quality review can distinguish extra candidate text, omitted reference text, and substitutions.
- Files: `tool/asr_transcript_eval.dart`, `test/tool/asr_transcript_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added a regression that verifies insertion/deletion/substitution counts sum to the minimum character edit count => pending CI.
  - Flutter Quality Gate, work-log lint, analyzer and complete tests => pending CI.
- Notes: Counts come from a deterministic minimum-edit path from reference to candidate; they are diagnostic categories, not proof that a unit is a hallucination or an omission. No real-song quality gain is claimed.
- Commit: `feat: report ASR edit operation breakdown`
