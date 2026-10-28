# [2026-10-25 16:10] Add explicit forced-alignment HTTP adapter contract

- Scope: Add a typed HTTP client boundary for arbitrary-text forced alignment. Require explicit endpoint configuration and send audio, transcript text, and language separately; reject invalid, unordered, or out-of-audio spans.
- Files: lib/features/transcription/data/services/forced_alignment_http_client.dart, test/features/transcription/forced_alignment_http_client_test.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added local HTTP-server tests for request shape, nested Qwen-style result parsing, non-success responses, blank input, non-monotonic timestamps, and audio-duration bounds. Remote CI must run Dart formatting, Flutter analysis, full tests, and work-log lint; this environment has no local Dart/Flutter SDK.
- Notes: Official Qwen3ForcedAligner.align supports audio + text + language, but the currently pinned Rust/Candle sidecar's /v1/transcribe request is ASR-only. This adapter is intentionally not wired into production until a separate local alignment bridge exposes the contract and is tested against the pinned runtime.
- Commit: `docs: log explicit forced-alignment adapter contract`
