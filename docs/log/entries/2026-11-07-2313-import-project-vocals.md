# [2026-11-07 23:13] Import existing vocal stems into projects

- Scope: Let desktop users import and replace existing vocal stems, preserve revision-checked project writes and use the stem for transcription and alignment.
- Files: Project stem importer, domain port, app assembly, detail screen and tests; transcription and editor path tests; README, PRD, work-log navigation and handoff.
- Validation:
  - Pinned Flutter GitHub Actions run 43021086377 passed dependency install, dart format, targeted project/widget/transcription/editor/documentation/architecture tests and flutter analyze --no-pub --no-fatal-infos lib test tool.
  - Work-log write/check run separately; final PR checks to be reviewed. Local Flutter/Dart unavailable.
- Notes: No automatic source separation, synchronization, audio-content validation, physical-device, native picker or real ASR verification. Failed-save copies and replaced files are retained to avoid deleting referenced audio.
- Commit: `Allow importing existing project vocal stems`
