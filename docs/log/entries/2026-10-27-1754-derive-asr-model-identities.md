# [2026-10-27 17:54] Derive ASR model identities from runtime configuration

- Scope: Keep fusion-result metadata and persisted project transcription records aligned with the actual configured Qwen ASR, ForcedAligner, and Whisper model paths instead of hardcoded model-size labels.
- Files: `lib/features/transcription/domain/models/transcription_model_identity.dart`, `lib/features/transcription/data/services/high_quality_transcription_service.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`, `test/features/transcription/transcription_model_identity_test.dart`, `test/high_quality_transcription_service_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added regression coverage for Qwen ASR 0.6B/1.7B, a non-default 1.5B aligner, Whisper medium/large-v3, custom Windows paths, and metadata produced by the fusion service.
  - GitHub Actions Flutter Quality Gate: pending for this branch; this execution environment has Git but no Dart/Flutter SDK, so local formatting, analysis, and tests could not be run.
- Notes: The identifier is based on the configured path's final component and deliberately omits an absolute local path. It is not a hash of the loaded weights and does not substitute for recording a real model revision/runtime version in benchmark provenance.
- Commit: `feat: derive ASR model identity from runtime configuration`
