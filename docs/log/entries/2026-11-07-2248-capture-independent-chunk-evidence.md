# [2026-11-07 22:48] Capture independent ASR chunk evidence

- Scope: Capture complete, source-verified original dual-ASR snapshots for long-audio chunks without merging overlap or using them as current-draft consensus.
- Files: Chunk evidence schema, resumable chunk service, domain and service regressions, handoff and log navigation.
- Validation:
  - dart format changed Dart files in Actions 43186086748 => formatted; patch applied locally.
  - flutter analyze --no-fatal-infos in Actions 43186086748 => no errors or warnings; info diagnostics remain.
  - Focused chunk, single-input and high-quality transcription tests in Actions 43186086748 => 152 passed.
- Notes: SHA and duration checks are point-in-time observations, not locks; checkpoint digests detect accidental corruption but are not signatures. Old or incomplete checkpoints cannot create evidence. No UI consumption, real recordings or real FFmpeg validation; #319 stays open.
- Commit: `Document chunk evidence capture`
