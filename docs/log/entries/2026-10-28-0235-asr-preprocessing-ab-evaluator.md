# [2026-10-28 02:35] Add paired A/B evaluation for shared ASR preprocessing

- Scope: Add a strict paired evaluator comparing per-engine normalization with shared normalized audio, reusing transcript metrics while rejecting changed source audio, references, engine coverage, model revisions, or runtime versions.
- Files: `tool/asr_preprocessing_ab_eval.dart`, `test/tool/asr_preprocessing_ab_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - GitHub Actions Quality Gate run [40562395476](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40562395476) on formatter head `7b770def21d4db396d9090157b147bfa56ac94d2`: Dart format passed, `flutter analyze lib test` passed, repository quality gate passed, and `flutter test` reported 758 tests passed.
  - That run emitted one work-log warning because this entry's commit subject did not match the actual implementation commit; the subject is corrected in this revision so the harness can check cleanly.
  - Renamed the test import prefix to satisfy the analyzer guidance for lower_case_with_underscores.
  - Local `dart format`, `flutter analyze`, and `flutter test` were not run because this environment has no Dart/Flutter SDK.
- Notes: No audio, lyrics, or measured accuracy data is fabricated. The tool requires actual input hashes and strict provenance; a valid result only measures the collected corpus and does not prove how representative the songs are.
- Commit: `feat: add paired ASR preprocessing evaluator`
