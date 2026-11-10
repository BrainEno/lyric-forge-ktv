# [2026-11-07 23:52] Protect transcription queue when resources are busy

- Scope: Preserve batch recognition items when the ASR resource is busy, explain the pause and permit explicit retry without treating contention as a failed song or an installation fault.
- Files: Queue model, file queue, queue panel, queue and widget tests, handoff, index, entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42785392999: format after dependency resolution, queue, busy-panel, environment recovery and protective-pause contract tests, and flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Temporary Actions work-log run checked formatting and generated/checked navigation; final PR gate reported separately. Local Flutter/Dart unavailable.
- Notes: Typed busy pauses persist across restart and require manual resume, which may pause again if still busy. Manual pause wins a race; no retry timer is added. Other ASR operations are not yet wired to the coordinator, and real devices/models were not tested.
- Commit: `Protect transcription queue when resources are busy`
