# [2026-10-26 21:30] Clarify ASR smoke-test scope versus lyric accuracy

- Scope: Prevent the real-audio ASR smoke test from implying that a successful pipeline run proves lyric completeness or recognition accuracy.
- Files: `lib/features/settings/presentation/widgets/asr_end_to_end_smoke_test_card.dart`, `docs/high_quality_asr.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, this entry.
- Validation: Copy-only UI change. The branch's Flutter Quality Gate will validate Dart format, analysis and tests; it does not perform an acoustic accuracy benchmark.
- Notes: Success messages now say the runtime/persistence path completed and explicitly state that the smoke test does not score missing lines, wrong words or timing accuracy. Users are directed to inspect the created project manually.
- Commit: `Clarify that ASR smoke test does not measure lyric accuracy`
