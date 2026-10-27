# [2026-10-27 19:20] Share one normalized audio input across ASR engines

- Scope: Make Highest Quality local transcription prepare one canonical 16 kHz mono signed 16-bit PCM WAV per job and pass the same file to Qwen and Whisper, while keeping standalone adapter preprocessing, cancellation, and artifact provenance intact.
- Files: `lib/features/transcription/domain/models/transcription_models.dart`, `lib/features/transcription/data/services/high_quality_transcription_service.dart`, `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`, `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`, `test/high_quality_transcription_service_test.dart`, `docs/high_quality_asr.md`, `docs/local_transcription.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added a regression test that verifies the normalization preparer is invoked once and both mocked engines receive the same normalized path for both engine orders.
  - Initial CI caught format-only differences. The exact formatter diffs were applied; final validation must be read from the latest PR head checks.
  - Local `dart format`, `flutter analyze`, and `flutter test` were not run because this execution environment has no Dart/Flutter SDK.
- Notes: The normalized WAV is regenerated once per Highest Quality job and retained after success because result/project metadata refer to it. Partial output is removed on failure/cancellation; no cross-run cache or measured acoustic accuracy claim is introduced. The implementation also guards against overwriting the original audio when source and target paths coincide.
- Commit: `feat: share normalized audio between ASR engines`
