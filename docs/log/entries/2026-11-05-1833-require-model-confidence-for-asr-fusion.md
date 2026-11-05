# [2026-11-05 18:33] Require model confidence for automatic ASR fusion

- Scope: Fix P1 issue #331 by preventing unscored placeholders and heuristic-adjusted scores from independently triggering automatic secondary-engine lyric replacement; preserve disagreements as review candidates.
- Files: `lib/features/transcription/data/services/high_quality_transcription_service.dart`; `test/high_quality_transcription_service_test.dart`; this work-log entry and generated work-log navigation.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run [42012105849](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/42012105849) passed on code/test head `9f01c7b`, including work-log preflight, changed-Dart formatting, analyzer, and full repository tests. A final-head run is required after the documentation refresh.
- Notes: Automatic confidence-based replacement now requires both engine confidences to have source `model`. Mixed fallback-line sources aggregate conservatively (`unscored` takes precedence over `heuristic`); local Flutter/Dart SDKs are unavailable. Issue #331 remains open pending final-head verification.
- Commit: `fix: require model confidence for automatic ASR fusion`
