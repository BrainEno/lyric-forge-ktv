# [2026-10-24 19:15] Exercise Qwen download HTTP fallback behavior

- Scope: Add deterministic local HTTP integration coverage for the managed Qwen downloader's real HEAD/GET requests, ModelScope manifest fallback, byte-range resume, checksum verification, and cross-source checksum mismatch rejection.
- Files: lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart, test/features/transcription/managed_model_asr_runtime_manager_http_test.dart, docs/asr_runtime_installation.md, work-log navigation.
- Validation: GitHub Actions must run the new localhost HTTP tests together with Flutter analyze, the full unit suite, and existing ASR validation workflows. This test validates the download behavior with small fixtures; it does not claim a live multi-gigabyte model download or native model-load test.
- Notes: Endpoint URI builders default to the official Hugging Face and ModelScope routes. Injection exists to target a local HTTP server in tests only; the shipped defaults and source trust policy remain unchanged.
- Commit: `test: exercise Qwen download HTTP behavior`
