# [2026-11-07 22:44] Protect partial project stores

- Scope: Reject incomplete project stores before they can overwrite saved projects and lyric documents, and avoid treating a partial project scan as a missing lyric association.
- Files: FileProjectRepository, project repository and playback lyric read-failure tests, index, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42382838232 passed focused project, player and atomic-persistence tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks reported separately. git diff --check ran locally.
- Notes: Non-object records, duplicate project IDs and invalid project data refuse loading and mutations without touching the canonical file or backup; shallow recovery validation remains unchanged. A new repository is needed after external repair because the initial load failure is cached. Cross-process modifications after load and partial media metadata reads remain out of scope. No native playback or manual UI checks performed.
- Commit: `fix: protect partial project stores`
