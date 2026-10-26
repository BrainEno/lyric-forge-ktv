# [2026-10-26 16:50] Capture local ForcedAligner results into evaluation corpus

- Scope: Add a privacy-bounded capture command so local /v1/align responses can be collected in the repeatable evaluation corpus with seconds converted to integer milliseconds.
- Files: `tool/forced_alignment_eval.dart`, `test/tool/forced_alignment_eval_test.dart`, `docs/high_quality_asr.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/log/entries/2026-10-26-1650-forced-align-local-capture.md`.
- Validation: Local Dart/Flutter tools are unavailable in this execution environment; GitHub Actions Flutter Quality Gate must validate the PR head, including work-log lint and the full test suite.
- Notes: The capture command only targets loopback /v1/align, preserves empty output, validates timestamps and bounds, and never repairs timing. No real audio was available here, so acoustic accuracy is not claimed.
- Commit: `Capture local ForcedAligner results for evaluation`
