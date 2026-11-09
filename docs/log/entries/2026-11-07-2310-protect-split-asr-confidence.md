# [2026-11-07 23:10] Protect split ASR confidence evidence

- Scope: Keep split secondary-ASR evidence in review when any scored segment is low, and explain confidence rather than claiming text disagreement.
- Files: Consensus analyzer, ASR-first pipeline, targeted tests, ASR review, handoff, index, this entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42626819397: dart format on changed Dart files after flutter pub get passed.
  - Pinned Flutter Actions run 42626819397: flutter analyze --no-pub --no-fatal-infos lib test tool passed.
  - Pinned Flutter Actions run 42626819397: flutter test --no-pub --reporter expanded test/features/lyrics/domain/proofreading passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: Scored segments are checked individually at the existing threshold; unscored placeholders are ignored and the aggregate mean remains unchanged. Nearby unrelated segments may conservatively trigger review; repetition analysis still uses the mean and its own threshold. No real-song benchmark or manual UI/device verification.
- Commit: `Protect low confidence split ASR evidence`
