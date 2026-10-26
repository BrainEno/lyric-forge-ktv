# [2026-10-26 15:05] Expose token-level forced alignment audition in proofreading

- Scope: Make ForcedAligner review evidence actionable by exposing each aligned token's timestamp interval and a one-click bounded audition from the proofreading proposal dialog.
- Files: lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart, lib/features/lyrics/presentation/screens/lyric_editor_screen.dart, test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart, docs/work_log.md, docs/work_log_archive.md, docs/work_log_index.md, docs/handoff.md, this entry.
- Validation: Added a widget regression test that expands a token-evidence row, verifies its timestamp/confidence display, and verifies the callback receives the expected source line and token. The PR's remote Flutter Quality Gate is the authoritative test/analyzer check; no local Dart/Flutter SDK is available in this execution environment.
- Notes: Token audition uses the existing bounded playback-window service with a 250 ms lead-in and respects document global offset/audio duration. Token times remain review-only evidence; accepting a proofreading proposal does not automatically change lyric timestamps.
- Commit: `feat: audition forced alignment word intervals`
