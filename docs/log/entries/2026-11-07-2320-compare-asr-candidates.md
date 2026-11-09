# [2026-11-07 23:20] Compare ASR candidate versions

- Scope: Show differences between existing dual-ASR candidates and allow restoring the original primary candidate without changing timing.
- Files: Lyric inspector, inspector widget tests, open-issue/product follow-up, handoff, index, this entry and generated work-log navigation.
- Validation:
  - Pinned Flutter Actions run 42630271940: formatted changed Dart files after flutter pub get.
  - Pinned Flutter Actions run 42630271940: flutter analyze --no-pub --no-fatal-infos lib test tool passed. Initial run 42629987426 had an unnecessary non-null assertion warning, which was removed.
  - Pinned Flutter Actions run 42630271940: lyric inspector widget and character diff service tests passed. Local Flutter/Dart unavailable; final PR checks reported separately.
- Notes: Candidate data can be absent, incomplete or wrong; legacy data without a known original is compared with current edits. No independent model rerun, full version comparison, automatic correction, real-song accuracy or manual device/UI validation in this phase. See the follow-up plan for open issues and next steps.
- Commit: `Compare both ASR candidates in the inspector`
