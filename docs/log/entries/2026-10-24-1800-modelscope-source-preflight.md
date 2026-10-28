# [2026-10-24 18:00] Validate ModelScope manifest as part of source preflight

- Scope: The advanced settings connectivity check must validate the actual prerequisites of each official Qwen source. ModelScope is available only when both the repository-file manifest API and the model shard's one-byte Range endpoint work.
- Files: lib/features/transcription/domain/services/asr_download_connection_checker.dart, lib/features/transcription/data/services/asr_download_connection_checker.dart, lib/features/transcription/presentation/widgets/transcription_config_dialog.dart, test/features/transcription/asr_install_experience_contract_test.dart, test/features/transcription/asr_download_connection_report_test.dart, test/features/transcription/asr_source_preflight_contract_test.dart, docs/asr_runtime_installation.md.
- Validation: Verify report-summary behavior and source-contract checks under the full Flutter Quality Gate and ASR workflows. This preflight validates connectivity and metadata shape only; it is not a full model download/runtime smoke test.
- Notes: ModelScope's documented client uses `/api/v1/models/<model_id>/repo/files?Recursive=true` and `/models/<model_id>/resolve/master/<path>`. The downloader also requires the manifest, so checking only the file URL is insufficient.
- Commit: `fix: verify ModelScope manifest during download preflight`
