# [2026-11-05 18:33] Require model confidence for automatic ASR fusion

- Scope: Fix P1 issue #331 by preventing unscored placeholders and heuristic-adjusted scores from independently triggering automatic secondary-engine lyric replacement; preserve disagreements as review candidates.
- Files: `lib/features/transcription/data/services/high_quality_transcription_service.dart`; `test/high_quality_transcription_service_test.dart`; this work-log entry and generated work-log navigation.
- Validation:
  - `git diff --check` => passed.
  - Pinned Flutter Quality Gate run [42012589740](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/42012589740) passed on code/test head `f33ee103`, including work-log preflight, changed-Dart formatting, analyzer, and full repository tests.
- Notes: Automatic confidence-based replacement now requires both engine confidences to have source `model`. Mixed fallback-line sources aggregate conservatively (`unscored` takes precedence over `heuristic`); local Flutter/Dart SDKs are unavailable. Attempted to close #331 after validation, but GitHub returned `Resource not accessible by integration`; issue remains open and should be closed manually: https://github.com/BrainEno/lyric-forge-ktv/issues/331.
- Commit: `fix: require model confidence for automatic ASR fusion`
