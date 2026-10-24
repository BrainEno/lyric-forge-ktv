# [2026-10-24 22:30] Recover Qwen downloads when source metadata differs

- Scope: Fix a real Windows setup failure where Hugging Face HEAD claimed a 206-byte `chat_template.json`, the resolved GET returned 1161 bytes, and ModelScope advertised the actual file size and SHA-256. Distinguish unsafe cross-source continuation from a safe full-file restart against an independently verified source.
- Files: `lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart`, `test/features/transcription/managed_model_asr_runtime_manager_http_test.dart`, `docs/asr_runtime_installation.md`, work-log navigation.
- Validation: Add localhost HTTP regression coverage for stale Hugging Face size metadata (206 expected, 1161 returned), full ModelScope fallback, and SHA-256 enforcement when source metadata differs. Run Flutter analysis, the complete test suite, work-log lint, and ASR validation workflows. Real Windows + RTX 5080 large-file download and native dual-engine load remain manual acceptance items.
- Notes: Compatible metadata may resume an existing partial. Incompatible metadata must discard the Hugging Face partial, fetch the affected file from byte zero using a source-specific partial file, and verify it against ModelScope's own manifest size and SHA-256.
- Commit: `fix: recover Qwen downloads when source metadata differs`
