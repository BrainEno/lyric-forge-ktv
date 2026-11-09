# [2026-11-07 23:58] Orchestrate independent model reruns

- Scope: Connect selected-engine runtime readiness, independent transcription and durable review candidates without replacing current lyrics.
- Files: Independent rerun workflow and focused tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42658407465: format after dependency resolution, independent workflow/rerun/candidate-store tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run: formatting and work-log write/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Default factories create actual native engine adapters, but tests use fakes and no production caller exists. App-wide ASR/aligner/install coordination is required before UI wiring; an idle Qwen server may retain GPU memory. Cancellation is refused once candidate persistence begins. Whole-file runs, model contents and real-song accuracy remain unverified.
- Commit: `Orchestrate independent model reruns`
