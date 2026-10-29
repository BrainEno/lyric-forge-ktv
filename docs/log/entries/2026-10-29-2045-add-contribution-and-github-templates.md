# [2026-10-29 20:45] Add contribution guidance and GitHub issue/PR templates

- Scope: Add a newcomer-facing contribution guide based on `AGENTS.md`, a structured bug-report form, a structured feature-request form, and a pull-request checklist for validation, platform testing, privacy, and data-safety risks.
- Files: `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, this entry, `docs/work_log.md`, `docs/work_log_archive.md`, and `docs/handoff.md`.
- Validation: Templates were reviewed for required reproduction/platform/version fields, safe handling of logs and copyrighted audio, product-fit expectations, and explicit reporting of unrun checks. Final-head Flutter Quality Gate must validate the work-log contract and repository tests; local Flutter/Dart SDKs are unavailable here.
- Notes: This is the companion slice of issue #215 and is deliberately scoped to contributor workflow and intake templates. It must be rebased after the README/package metadata slice in PR #250 merges because both slices update generated work-log navigation.
- Commit: `docs: add contribution workflow and GitHub templates`
