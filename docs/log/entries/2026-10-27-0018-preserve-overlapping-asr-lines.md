# [2026-10-27 00:18] Preserve novel secondary ASR lines inside overlapping segments

- Scope: Improve highest-quality ASR recall when a secondary recognizer finds a distinct lyric/ad-lib inside a long primary segment; timestamp overlap alone must not mark the secondary line as already represented.
- Files: `lib/features/transcription/data/services/high_quality_transcription_service.dart`, `test/high_quality_transcription_service_test.dart`, `docs/high_quality_asr.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, this entry.
- Validation:
  - `flutter test test/high_quality_transcription_service_test.dart` => regression covers both Qwen-primary and Whisper-primary fusion directions, including a contained internal word at a non-matching time position; final run must be confirmed by remote CI.
  - `dart format` and the repository Flutter Quality Gate => rerun on the final PR head.
- Notes: Contained text is paired only when its timestamps fit the expected text position or the matching segment edge. Non-contained lexical matching requires strong temporal overlap and comparable duration. Unmatched secondary output remains confidence-capped at 60 and requires human review. No real-song WER/recall improvement is claimed until a manually reviewed audio corpus is evaluated.
- Commit: `Preserve novel secondary ASR lines that overlap a primary segment`
