# [2026-10-27 19:20] Share one normalized audio input across ASR engines

- Scope: Make Highest Quality local transcription prepare one canonical 16 kHz mono signed 16-bit PCM WAV per job and pass the same file to Qwen and Whisper, while keeping standalone adapter preprocessing, cancellation, and artifact provenance intact.
- Files: `lib/features/transcription/domain/models/transcription_models.dart`, `lib/features/transcription/data/services/high_quality_transcription_service.dart`, `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`, `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`, `test/high_quality_transcription_service_test.dart`, `docs/high_quality_asr.md`, `docs/local_transcription.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Flutter Quality Gate on implementation/documentation head `96e8f2c4c46d8e57262451da0a155be04d245741` passed: work-log preflight, changed-Dart format check, `flutter analyze lib test`, repository quality gate, and `flutter test` (752 tests passed). [Run 40496005845](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005845).
  - ASR client checks passed. [Run 40496005889](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005889).
  - Transcription settings validation passed, including settings/store contract and full Flutter regression suite. [Run 40496005834](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005834).
  - Transcription execution failure validation passed, including the full Flutter regression suite. [Run 40496005839](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496005839).
  - Transcription queue protective pause validation passed, including the full Flutter regression suite. [Run 40496006747](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40496006747).
  - Local `dart format`, `flutter analyze`, and `flutter test` were not run because this execution environment has no Dart/Flutter SDK.
- Notes: The normalized WAV is regenerated once per Highest Quality job and retained after success because result/project metadata refer to it. Cleanup of partial output is attempted on failure/cancellation; no cross-run cache or measured acoustic accuracy claim is introduced. The implementation also guards against overwriting the original audio when source and target paths coincide.
- Commit: `feat: share normalized audio between ASR engines`
