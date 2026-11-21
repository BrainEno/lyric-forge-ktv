# [2026-12-11 09:30] One-click follow-ups of the vocal check

- Scope: round 24. The user asked for two one-click actions on top of the vocal check (D-044): recognise the stretches with singing but no lyrics right away, and restore rows the check deleted by mistake. Changes (D-045):
  - `LyricVocalCheckActions` (lyrics domain): plans the recognition window for a stretch (0.3 s of context on each side, never into the neighbouring rows or past the audio, refused under 0.5 s and over 90 s), clips recognised rows into it (sorted, non-overlapping, fragments under 120 ms dropped, word timing kept only when complete) and inserts them as new rows with ids while row-indexed review evidence moves along; dismisses a stretch; restores chosen or all removed rows at their recognised times, reporting overlaps.
  - `LyricVocalCheckRecord`: `restoredLines` and `dismissedSpans` counters (written only when non-zero, so older builds read the record unchanged), `withRestored`, `withDismissed`, `writeTo`; `LyricVocalCheckRemovedLine.toLine`.
  - `LyricVocalGapDialog`: recognises the stretch as soon as it opens (Qwen3-ASR; switching to Whisper or to the previous/next stretch re-runs at once), stop, run again, preview, insert, or "这里没有歌词".
  - `LyricVocalRestoreDialog`: one checkbox per removed row (all checked), select all/none, preview of the old time; restored rows are marked as hand edits. `lyricRestoreAllRemovedLinesEdit` restores everything without a dialog.
  - Recognition summary card: a "识别 m:ss.s" button per listed stretch (plus a walk-through button past three), "逐行查看" and "全部恢复" when rows were removed, and the restored/dismissed counts in the expanded text. The card raises a `LyricVocalCheckRequest` through `LyricProofreadActions.onVocalCheckAction`.
  - `LyricBatchTextToolsCoordinator.openVocalCheck` and two new batch tools (`vocalGapRecognition`, `restoreRemovedLines`) in the proofreading menu's correction group; all paths share the stale-document check and apply one undoable edit.
- Files:
  - New: `lib/features/lyrics/domain/services/lyric_vocal_check_actions.dart`, `lib/features/lyrics/presentation/widgets/lyric_vocal_gap_dialog.dart`, `lyric_vocal_restore_dialog.dart`, `lyric_vocal_check_request.dart`.
  - `lib/features/lyrics/domain/models/vocal_check_record.dart`, `lib/features/lyrics/presentation/controllers/lyric_batch_text_tools_coordinator.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart`, `lyric_editor_actions.dart`, `lyric_editor_content.dart`, `lyric_proofread_menu_button.dart`, `lyric_recognition_summary_card.dart`.
  - New tests: `test/features/lyrics/domain/services/lyric_vocal_check_actions_test.dart`, `test/features/lyrics/presentation/widgets/lyric_vocal_gap_dialog_test.dart`, `lyric_vocal_restore_dialog_test.dart`, `lyric_recognition_vocal_actions_test.dart`; `lyric_proofread_menu_button_test.dart` lists the two new entries.
  - `docs/decisions.md` (D-045), `docs/high_quality_asr.md`, `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Inserted rows carry no second-engine evidence; like typed rows they need a listen.
  - The menu entries are available whenever the document has rows; without a vocal check record they explain that there is nothing to do.
- Commit: `Recognise unsung gaps and restore removed rows in one click`
