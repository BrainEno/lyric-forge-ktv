# [2026-11-07 18:43] Remove unused proofreading constants

- Scope: Remove unconsumed proofreading constants, clarify ratio versus percentage units, and guard retained constants against losing all production readers (#326).
- Files: Proofread constants, token aligner and strategy selector, liveness contract test, proofreading v2 plan, work-log navigation and handoff.
- Validation:
  - dart format changed Dart files after dependency resolution => passed in temporary GitHub Actions validation.
  - bash scripts/quality_gate.sh --skip-pub-get => passed in temporary GitHub Actions validation, including analyzer and full suite.
  - flutter test --no-pub --reporter expanded test/features/lyrics/domain/proofreading => passed in temporary GitHub Actions validation.
- Notes: The lexical liveness contract ignores comments and strings and is not a semantic Dart parser. Prior full-gate run 42364982248 failed on an unrelated intermittent Media Hub TLS Broken pipe; targeted proofreading tests passed. Algorithm values are unchanged.
- Commit: `Remove unused proofreading constants`
