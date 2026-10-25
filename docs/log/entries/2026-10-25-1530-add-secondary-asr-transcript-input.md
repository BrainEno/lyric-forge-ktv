# [2026-10-25 15:30] Add timestamped secondary ASR input to proofreading

- Scope: Expose an optional second ASR transcript in the ASR-first proofreading options and pass it to the existing consensus analyzer as independent timed evidence.
- Files: lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart, lib/features/lyrics/presentation/screens/lyric_editor_screen.dart, test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added a widget regression for capturing the optional secondary transcript. GitHub Actions must validate formatting, analysis, Flutter tests, and work-log lint; this environment has no local Flutter SDK.
- Notes: Only fully timestamped LRC/SRT/WebVTT input is accepted because the consensus analyzer matches evidence by time overlap. Imported confidence is conservatively set to 60 because the text importer does not expose calibrated ASR confidence. No transcript is auto-applied; disagreements remain review proposals.
- Commit: `docs: log ASR-first secondary transcript input`
