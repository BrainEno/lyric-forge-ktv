# [2026-10-23 02:34] Add universal Flutter quality gate

- Scope: Add a baseline GitHub Actions workflow that runs on every pull request targeting `main`, every push to `main`, and manual dispatch, without path filters. Reuse the repository quality gate for analysis, the full Flutter test suite, and work-log validation; verify this rollout against PR #147 and the merged main commit.
- Files: `.github/workflows/flutter-quality.yml`; `lib/features/lyrics/domain/proofreading/asr_consensus_analyzer.dart`; `lib/features/lyrics/domain/proofreading/asr_hallucination_filter.dart`; `lib/features/lyrics/domain/proofreading/asr_retiming_planner.dart`; `lib/features/lyrics/domain/proofreading/asr_repetition_analyzer.dart`; `lib/features/lyrics/domain/proofreading/reference_token_aligner.dart`; `lib/features/lyrics/data/services/local_lyric_file_export_service.dart`; `test/features/lyrics/domain/proofreading/reference_first_pipeline_test.dart`; `docs/work_log_index.md`; `docs/handoff.md`; `docs/work_log.md`; `docs/work_log_archive.md`; this entry.
- Validation:
  - GitHub Actions `flutter pub get` → passed.
  - Formatter step for newly added Dart files → passed; no new Dart files were introduced in this PR, so modified existing Dart files were not formatter-checked by this step.
  - `flutter analyze --no-pub --no-fatal-infos lib test` → passed; 3 info-level lints remain, with no errors or warnings.
  - `flutter test --no-pub --reporter expanded` → 609 tests passed.
  - `dart tool/work_log.dart check` → passed on the final PR run.
  - PR #147 Actions run `39831585131` → success; merged-main push run `39832028975` → success.
- Notes: Running Dart 3.47.7 formatting across the entire repository reported historical formatting differences in 217 of 331 Dart files; this change avoids unrelated mass reformatting and currently enforces formatting only for newly added Dart files. Full analyzer/tests cover `lib` and `test`. Repository branch-protection settings could not be read or updated through the connected GitHub API, so make the stable `Flutter Quality Gate / format-analyze-test-worklog` check required in repository Settings.
- Commit: ci: add universal Flutter quality gate
