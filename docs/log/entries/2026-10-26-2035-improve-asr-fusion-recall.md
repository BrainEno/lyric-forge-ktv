# [2026-10-26 20:35] Improve ASR fusion recall and confidence handling

- Scope: Improve the Windows high-quality ASR path after real-song testing exposed poor Qwen coverage. Use Whisper as the provisional RTX 5080 primary, compare the full-song Qwen transcript in both directions, and preserve secondary-only timed lyric lines as review-required suggestions.
- Files: lib/features/transcription/data/services/high_quality_transcription_service.dart, lib/features/transcription/data/services/native_transcription_profile_resolver.dart, lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart, test/high_quality_transcription_service_test.dart, test/transcription_hardware_profile_test.dart, docs/high_quality_asr.md, docs/local_transcription.md, docs/work_log.md, docs/handoff.md, this entry.
- Validation:
  - Added regression tests for Whisper-only and Qwen-only line recovery, row-index remapping after insertion, and the Windows profile's engine order.
  - `flutter test test/high_quality_transcription_service_test.dart test/transcription_hardware_profile_test.dart` — not run locally; this environment has no local Flutter/Dart SDK. Remote Flutter Quality Gate must validate the branch.
  - Real Windows RTX 5080 / Roadhouse Blues retest — pending a rebuilt application; this patch does not claim measured acoustic accuracy.
- Notes: Whisper-first is a provisional profile default based on the observed song-level failure, not a claim of universal Whisper superiority. Secondary-only rows are timestamp-sorted and capped at confidence 60 to force review; source transcript alternatives are remapped after insertions. Qwen lines without calibrated lexical confidence now use a neutral review-required score of 50 rather than an optimistic timing-derived 92. Source separation is still incomplete, so mixed-instrument audio may remain a quality bottleneck.
- Commit: `Prefer Whisper first and retain secondary-only lyric lines`
