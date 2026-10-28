# [2026-10-25 21:55] Wire forced alignment into proofreading proposals

- Scope: Add an orchestration service that sends explicit audio path, reference lyric text, and language to the native alignment endpoint, converts validated spans into proofreading evidence, and returns a visible warning when coverage is incomplete or the endpoint fails.
- Files: lib/features/transcription/data/services/forced_alignment_proofread_service.dart, test/features/transcription/forced_alignment_proofread_service_test.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, docs/work_log_index.md, this entry.
- Validation: Added local HTTP-server tests for successful evidence mapping, unmatched-line warning, and runtime failure fallback. Remote Flutter Quality Gate must confirm formatting, analysis, tests, and work-log lint; no local Dart/Flutter SDK is available in this execution environment.
- Notes: Alignment is review evidence only. The service never applies timestamps or edits lyric text; failure preserves the existing proposal and returns a warning. Native endpoint availability still depends on installing a runtime bundle rebuilt with the endpoint patch, and real-song accuracy remains unverified.
- Commit: `docs: log forced alignment proofreading service`
