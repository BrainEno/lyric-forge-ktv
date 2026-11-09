# [2026-11-09 23:29] Verify ASR source audio evidence

- Scope: Record a traceable input audio digest with dual-ASR snapshots and distinguish current, changed and unverified evidence for later review.
- Files: Independent evidence model, high-quality transcription and source verification services, their tests, product follow-up, handoff, log entry and generated navigation.
- Validation:
  - Pinned Flutter Actions run 42644514145: dart format after dependency resolution, focused evidence/high-quality/chunked/cancellation tests and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Pinned Flutter Actions final temporary run: formatting and work-log generation/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Source and internally generated shared WAV are hashed before/after recognition, with stat checks during reads; these are not locks or proof that no transient mutation occurred. Caller must check the actual selected input and revalidate before use. Model content, project revisions, external prepared inputs, chunks, UI, safe reruns and real-song accuracy remain out of scope.
- Commit: `Verify ASR source audio evidence`
