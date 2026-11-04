# [2026-11-04 21:20] Extend quality gate analysis to tooling scripts

- Scope: Resolve #334 by adding repository maintenance and ASR evaluation Dart tools to the shared analyzer scope on Bash and PowerShell, and pin that contract with a regression test.
- Files: `scripts/quality_gate.sh`, `scripts/quality_gate.ps1`, `test/ci_workflow_contract_test.dart`, this entry, generated `docs/work_log.md` and `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation:
  - `bash -n scripts/quality_gate.sh` => passed.
  - Static scope assertion and `git diff --check` => passed before the documentation follow-up.
  - Pinned Flutter Quality Gate run `41835929966` => passed on code/test head `197faf0`, including work-log preflight, formatting, analysis with `lib test tool`, and the complete test suite.
  - Local Flutter/Dart analysis, formatter, and tests => not run because the SDK is unavailable in this workspace. The documentation-only follow-up commit requires its own final-head gate.
- Notes: The shared gate still excludes the vendored `packages/desktop_multi_window/example/` demo app. Full tests exercise the ASR evaluation tools; the work-log CLI check remains a preflight. Specialist native, KTV recovery, runtime-release, and icon workflows are unchanged. PR #341 remains open for review; do not merge without user authorization.
- Commit: `docs: record tooling analyzer gate coverage`
