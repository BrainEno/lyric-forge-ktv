# [2026-10-29 20:00] Document LyricForge product and source-build setup

- Scope: Replace the Flutter starter README with an accurate LyricForge KTV overview, platform capability matrix, source-build instructions, local ASR requirements, Media Hub security boundaries, development checks, project layout, and MIT license reference. Replace the template package description and add the repository URL to `pubspec.yaml`.
- Files: `README.md`, `pubspec.yaml`, this entry, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`.
- Validation: Product claims were cross-checked against `AGENTS.md`, the current `pubspec.yaml`, the local ASR guide, responsive-layout standard, engineering roadmap, and `LICENSE`. No screenshot/demo was fabricated. Final-head Flutter Quality Gate must pass; local Flutter/Dart SDKs are unavailable here.
- Notes: Platform capabilities are qualified; automatic transcripts are described as editable drafts. `publish_to: none` remains unchanged. Contribution and GitHub templates are handled by the companion work item so this PR stays a small, reviewable slice.
- Commit: `docs: document LyricForge product and source-build setup`
