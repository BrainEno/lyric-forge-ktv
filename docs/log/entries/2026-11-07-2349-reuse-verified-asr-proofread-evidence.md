# [2026-11-07 23:49] Reuse verified ASR evidence for proofreading

- Scope: Allow explicit reuse of an independent project ASR transcript for V2 review after conservative baseline and audio checks.
- Files: Evidence loader and domain contract, editor assembly and V2 UI, loader and widget tests, work log, index and handoff.
- Validation:
  - dart format changed Dart files => passed in Actions 43148246398.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 43148246398.
  - Targeted loader, editor, dialog and architecture tests => passed in Actions 43148246398.
- Notes: Only matching primary drafts with verified single-input audio qualify; checks are not locks or proof of model accuracy. No real audio, device or screen-reader testing. Reference-first ForcedAligner and fused/chunked reuse remain open.
- Commit: `Reuse verified independent ASR evidence for proofreading`
