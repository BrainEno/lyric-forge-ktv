# [2026-11-07 16:18] Preserve project status on ASR cancellation

- Scope: Restore a project's original ready, editing or draft status when retranscription is cancelled, preserving its editable lyrics and other project data.
- Files: `local_project_transcription_workflow.dart`, `local_project_transcription_cancellation_test.dart`, `docs/handoff.md`, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs are unavailable; focused workflow tests, the full quality gate, Dart formatting and work-log new/write/check passed using the pinned SDK in GitHub Actions run 42354903212 on the preliminary head. Consult PR #366 for final-head results. `git diff --check` was run locally.
- Notes: Transient or error statuses retain the existing lyrics-based fallback. The cancellation update uses the latest manifest so newer lyric edits, stage and metadata are not overwritten. Real ASR hardware and UI cancellation remain unverified locally.
- Commit: `fix: restore project status after transcription cancellation`
