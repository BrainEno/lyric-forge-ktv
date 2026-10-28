# [2026-10-26 16:20] Surface ForcedAligner coverage diagnostics in review

- Scope: Complete the ForcedAligner diagnostics path from bounded domain matching through the service warning and the review dialog; explicitly handle successful empty responses as zero coverage.
- Files: lib/features/transcription/data/services/forced_alignment_proofread_service.dart, test/features/transcription/forced_alignment_proofread_service_test.dart, lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart, test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart, lib/features/lyrics/presentation/screens/lyric_editor_screen.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_index.md, docs/work_log_archive.md, this entry.
- Validation:
  - `flutter test test/features/transcription/forced_alignment_proofread_service_test.dart test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart` => targeted regressions added; execution pending remote CI because no local Flutter SDK is available.
  - `flutter analyze --no-pub` => not run locally; must be checked by the updated PR's Flutter Quality Gate.
  - `dart tool/work_log.dart check` => not run locally; summary and archive references were updated to reflect the new entry.
- Notes: Coverage, skipped-span count, and one-based unmatched row numbers are visible for manual review. Empty successful output no longer implies useful timing evidence. Source lyrics and line timestamps remain unchanged; synthetic tests do not prove real-song accuracy.
- Commit: `feat: surface forced-alignment diagnostics in review`
