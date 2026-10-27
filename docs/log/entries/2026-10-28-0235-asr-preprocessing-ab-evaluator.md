# [2026-10-28 02:35] Add paired A/B evaluation for shared ASR preprocessing

- Scope: Add a strict paired evaluator comparing per-engine normalization with shared normalized audio, reusing transcript metrics while rejecting changed source audio, references, engine coverage, model revisions, or runtime versions.
- Files: `tool/asr_preprocessing_ab_eval.dart`, `test/tool/asr_preprocessing_ab_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added synthetic unit coverage for per-engine pairing and deltas, changed source fingerprints, changed references, model/runtime drift, missing engine pairs, and unchanged-input detection.
  - GitHub Actions formatting, analysis, work-log lint, and full regression validation are pending for this commit.
  - Local `dart format`, `flutter analyze`, and `flutter test` were not run because this environment has no Dart/Flutter SDK.
- Notes: No audio, lyrics, or measured accuracy data is fabricated. The tool requires actual input hashes and strict provenance; a valid result only measures the collected corpus and does not prove how representative the songs are.
- Commit: `feat: compare ASR preprocessing paths on paired corpus`
