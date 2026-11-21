# [2026-12-12 09:30] Recognise all unsung gaps at once

- Scope: round 25. The user asked for the next round; the round 24 report proposed recognising every stretch with singing but no lyrics in one go and confirming once. Changes (D-046):
  - `LyricVocalGapBatch` (lyrics domain): plans one window per open stretch in timeline order (keeping unsendable ones with their reason) and applies the accepted insertions, all planned against the same document, in one pass: old rows keep their order and ids, rows of stretches between the same two rows are made consecutive (fragments under 120 ms dropped), row-indexed review evidence is remapped once (entries pointing past the rows are dropped), new rows get ids, and stretches can be dismissed in the same edit. `lyricOtherSpanEngine` names the fallback engine.
  - `LyricVocalCheckActions.toDocumentTimeline`: moves recognised rows and their word timing from the audio's timeline onto the document's; the single-stretch dialog uses it too.
  - `LyricVocalGapBatchDialog`: recognises every stretch one after another as soon as it opens, with progress; a stretch the chosen engine hears nothing in or fails on is tried once with the other engine (switchable); a busy runtime or a stop ends the run and keeps the results; "再识别没有结果的 N 处" continues; a checkbox per result, preview per window, and an option to mark the stretches that still have nothing as having no lyrics.
  - Recognition summary card: "全部识别（N 处）" with two or more open stretches, raising `LyricVocalGapBatchRequest`; the batch tools coordinator opens the dialog after the same audio and runtime checks as one stretch.
- Files:
  - New: `lib/features/lyrics/domain/services/lyric_vocal_gap_batch.dart`, `lib/features/lyrics/presentation/widgets/lyric_vocal_gap_batch_dialog.dart`.
  - `lib/features/lyrics/domain/services/lyric_vocal_check_actions.dart`, `lib/features/lyrics/presentation/controllers/lyric_batch_text_tools_coordinator.dart`, `lib/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart`, `lyric_vocal_check_request.dart`, `lyric_vocal_gap_dialog.dart`.
  - New tests: `test/features/lyrics/domain/services/lyric_vocal_gap_batch_test.dart`, `test/features/lyrics/presentation/widgets/lyric_vocal_gap_batch_dialog_test.dart`; card cases in `lyric_recognition_vocal_actions_test.dart`.
  - `docs/decisions.md` (D-046), `docs/high_quality_asr.md`, `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - A run takes about the sum of the stretches' recognition times; the fallback doubles it for stretches the first engine misses.
  - Inserted rows carry no second-engine evidence and need a listen, as in D-045.
- Commit: `Recognise all unsung gaps at once`
