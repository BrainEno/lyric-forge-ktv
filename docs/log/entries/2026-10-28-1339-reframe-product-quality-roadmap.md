# [2026-10-28 13:39] Reframe roadmap around open-source product quality

- Scope: Revise the second-review roadmap to match the product direction: open-source, local-first KTV software with commercial-grade functionality, without assuming monetization or treating hypothetical commercial-release concerns as engineering gates.
- Files: `docs/engineering_risks_roadmap.md`, `docs/work_log_index.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/log/entries/2026-10-28-1339-reframe-product-quality-roadmap.md`, `docs/handoff.md`.
- Validation:
  - Reframed the roadmap priority and implementation order around data integrity, process recovery, network upload limits, runtime integrity, real-song audio evaluation, separation, and install/upgrade behavior.
  - Replaced the Qwen runtime's P0 commercial-redistribution blocker with a bounded artifact-provenance task. The note applies only if that specific runtime is bundled/distributed; it does not block local evaluation or unrelated development.
  - Updated index and handoff navigation to describe the open-source product-quality objective.
  - Local Dart/Flutter checks are unavailable in this environment; the GitHub Actions quality gate remains the final automated check.
- Notes: Documentation-only update. No application source or runtime binaries changed. Required third-party notices remain scoped to actual bundled artifacts; no general legal-review or commercial-use approval is assumed.
- Commit: `docs: reframe roadmap around open-source product quality`
