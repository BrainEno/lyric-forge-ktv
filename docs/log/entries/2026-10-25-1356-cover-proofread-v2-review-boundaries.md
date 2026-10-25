# [2026-10-25 13:56] Cover proofreading v2 review boundaries

- Scope: Add widget regressions for cancelling the proofreading review and preserving locked/manual-reviewed rows when the user chooses green-only application.
- Files: `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, this entry.
- Validation: The current execution environment has no repository checkout or Dart/Flutter executables, so local formatting, analysis, targeted Flutter tests, and work-log lint were not run. The pull request's GitHub Actions quality gate must pass before merge.
- Notes: Automated widget checks do not replace real-device viewport checks, row audition, apply/undo behavior, or the Windows RTX 5080 audio self-check. ASR-first still lacks a second-transcript input; arbitrary-text ForcedAligner integration remains follow-up work.
- Commit: `test: cover proofreading review boundaries`
