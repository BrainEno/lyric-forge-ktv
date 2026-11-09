# [2026-11-07 23:00] Guard incomparable ASR review evidence

- Scope: Keep empty-normalized ASR evidence in review rather than marking it as agreement.
- Files: ASR consensus analyzer, first-pass pipeline and review reason, Chinese label, targeted tests, ASR review, log entry, generated navigation, index and handoff.
- Validation:
  - Pinned Flutter Actions run 42623215036: dart format on changed Dart files passed.
  - Pinned Flutter Actions run 42623215036: flutter analyze --no-pub --no-fatal-infos lib test tool passed; earlier run 42622964603 used fatal infos and failed.
  - Pinned Flutter Actions run 42623215036: targeted consensus, first-pass pipeline and Chinese review strings tests passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: No lyric text or timestamps are rewritten. Normalization uses existing rules, which do not discard every Unicode symbol; over-budget comparisons remain conservative. Protected lines remain locked. Real-song accuracy, boundary joins and manual UI/device behavior are not validated.
- Commit: `Guard incomparable ASR review evidence`
