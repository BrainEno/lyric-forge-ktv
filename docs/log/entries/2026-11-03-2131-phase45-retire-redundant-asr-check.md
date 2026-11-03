# [2026-11-03 21:31] Retire redundant ASR client workflow

- Scope: Start Phase 4.5 with one independently verifiable CI simplification. Remove the ASR client-only analyzer and single-test workflow because the universal Flutter Quality Gate runs repository-wide analysis and the complete Flutter test suite for every PR to main.
- Files: `.github/workflows/asr-client-checks.yml` (removed), `test/ci_workflow_contract_test.dart`, `docs/reviews/2026-10-31-recognition-quality-and-ux-deep-review.md`, `docs/work_log_index.md`, `docs/handoff.md`, and generated work-log navigation files.
- Validation:
  - `dart format` on changed Dart files => passed.
  - `flutter test test/ci_workflow_contract_test.dart` => passed.
  - `bash scripts/quality_gate.sh --skip-pub-get` => passed (analyze, full test suite, work-log preflight; CI run 41645039894).
  - `dart tool/work_log.dart write` and `dart tool/work_log.dart check` => passed.
- Notes: No production code, runtime behavior, ASR algorithm, or lyric semantics changed. KTV, native-platform, runtime-release, and icon workflows remain untouched; this slice does not authorize deleting other specialist checks without an equivalent coverage audit.
- Commit: `ci: retire duplicate ASR client workflow`
