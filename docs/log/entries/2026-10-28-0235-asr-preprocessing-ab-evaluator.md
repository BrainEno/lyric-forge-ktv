# [2026-10-28 02:35] Add paired A/B evaluation for shared ASR preprocessing

- Scope: Add a strict paired evaluator comparing per-engine normalization with shared normalized audio, reusing transcript metrics while rejecting changed source audio, references, engine coverage, model revisions, or runtime versions.
- Files: `tool/asr_preprocessing_ab_eval.dart`, `test/tool/asr_preprocessing_ab_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Latest code/test head `2ba8f011be7467c3a2f4b7cec078657ffa3b19ee`: Flutter Quality Gate [40564197582](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40564197582) passed. Work-log lint reported 0 errors / 0 warnings; changed-Dart format check reported 2 files, 0 changes; `flutter analyze lib test` and the repository quality gate passed; `flutter test` reported 759 tests passed.
  - The earlier formatter differences and the initial WER fixture's incorrect denominator expectation were corrected using the actual CI output.
  - Added a WER regression for pairs where only one side supports WER (such as CJK text appearing in only one output); the aggregate now uses the same comparable pair subset on both sides.
  - Local `dart format`, `flutter analyze`, and `flutter test` were not run because this environment has no Dart/Flutter SDK.
- Notes: No audio, lyrics, or measured accuracy data is fabricated. The tool requires actual input hashes and strict provenance; a valid result only measures the collected corpus and does not prove how representative the songs are.
- Commit: `feat: add paired ASR preprocessing evaluator`
