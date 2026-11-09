# [2026-11-07 23:30] Preserve independent ASR transcript evidence

- Scope: Retain independent pre-fusion lyrics and timing after successful single-input dual-ASR recognition for a later comparison workflow.
- Files: Independent ASR evidence model, high-quality and chunked transcription services and tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42636864433: dart format on changed Dart files after flutter pub get passed.
  - Pinned Flutter Actions run 42636864433: flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Pinned Flutter Actions run 42636864433: independent evidence, high-quality transcription and chunked transcription tests passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: Snapshots omit engine metadata and raw file paths; invalid, degraded and merged chunk evidence is not exposed as a complete pair. No audio or model hash verifies provenance. Old projects, single-engine and chunked output lack full snapshots; document metadata grows. No UI consumer, safe rerun, automated correction or real-song accuracy verification.
- Commit: `Preserve independent ASR transcript evidence`
