# [2026-11-07 23:45] Build isolated ASR rerun candidates

- Scope: Provide an isolated, selected-engine rerun that returns the current lyrics and a new in-memory candidate without writing over the project.
- Files: Isolated rerun service, shared project input resolver, existing project transcription workflow, focused tests, product follow-up, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42648958879: format after dependency resolution, candidate/standard-workflow cancellation/audio verification tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run: format check and work-log write/check; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: No production caller, UI or durable version store yet. Isolated factories must provide exclusively owned adapters; direct whole-file inference is not chunked. Model references are not model hashes; source and revision checks are not locks and require revalidation before use. Real engines and songs not evaluated.
- Commit: `Build isolated ASR rerun candidates`
