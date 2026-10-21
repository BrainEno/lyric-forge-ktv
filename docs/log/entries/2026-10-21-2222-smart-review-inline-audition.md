# [2026-10-21 22:22] Add inline audition to smart review rows

- Scope: Reduce review friction by letting the user audition a flagged lyric from its own smart-review row without opening the inspector. The action reuses the editor's current playback session and existing effective-start-time preview logic.
- Files: lib/features/lyrics/presentation/screens/lyric_editor_screen.dart; lib/features/lyrics/presentation/widgets/smart_review_audition_button.dart; test/features/lyrics/presentation/widgets/smart_review_audition_button_test.dart; docs/lyric_review_alignment_plan.md; docs/work_log_index.md; docs/handoff.md.
- Validation: GitHub source/patch wiring checked. Added widget tests for callback, disabled state and minimum 48dp target. Dart/Flutter formatter, analyzer and tests were not run in this execution environment.
- Notes: The button appears only in Smart Review mode and only when the project has an audio asset. It does not mutate lyric text/timing, change the selected review order, or open the compact inspector. Existing row-tap behavior remains unchanged.
- Commit: Add inline audition to smart review rows
