# [2026-10-27 18:54] Unify audio normalization across local ASR paths

- Scope: Keep full-audio Qwen, full-audio Whisper, and resumable long-audio chunk extraction on one shared 16 kHz mono signed 16-bit PCM output contract, preventing normalization options from drifting between adapters.
- Files: `lib/features/transcription/data/services/asr_audio_normalization.dart`, `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`, `lib/features/transcription/data/services/whisper_cpp_transcription_service.dart`, `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`, `test/features/transcription/asr_audio_normalization_test.dart`, `docs/high_quality_asr.md`, `docs/local_transcription.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Flutter Quality Gate run [40491807971](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807971) on code head `394f4e21cd7eb6a21673fe1a66fe5ff49b301c8a`: work-log preflight and changed-Dart format check passed; repository quality gate passed; `flutter test` reported 751 tests passed.
  - ASR client checks run [40491807965](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807965): passed.
  - Transcription settings validation run [40491807895](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807895): passed, including the full regression suite.
  - Transcription execution failure validation run [40491807959](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40491807959): passed, including the full regression suite.
  - No local Dart/Flutter SDK was available; validation was performed in GitHub Actions.
- Notes: The change preserves the existing FFmpeg audio-stream selection and per-adapter conversion strategy. It unifies the normalization argument contract but does not introduce one shared converted WAV, prove byte-identical intermediate files, or claim any acoustic recognition gain.
- Commit: `refactor: unify ASR audio normalization`
