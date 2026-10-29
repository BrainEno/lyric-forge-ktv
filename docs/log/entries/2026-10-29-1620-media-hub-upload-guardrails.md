# [2026-10-29 16:20] Bound Media Hub incoming upload resources

- Scope: Prevent a paired device from exhausting disk space or monopolizing the Media Hub upload handler with oversized, stalled, or concurrent incoming audio requests.
- Files: `lib/features/transfer/data/services/http_media_hub_service.dart`, `test/features/transfer/http_media_hub_upload_test.dart`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, and this entry.
- Validation: No local Flutter/Dart SDK is available in this environment. The targeted upload tests, repository quality gate, KTV history/recovery validation, and Windows Debug build must pass on the final PR head before merge.
- Notes: Defaults are a 2 GiB per-file cap, 30-second idle timeout, 45-minute total deadline, 256 MiB free-space reserve, and periodic free-space checks during large transfers. At most two uploads may be active process-wide and one per session. Disk-space probes use PowerShell/.NET DriveInfo on Windows and `df -Pk` on Linux/macOS; unsupported probes fail closed with HTTP 507. Physical device upload behavior still needs a smoke test; the separate `#234` .part-name reservation race remains outside this task.
- Commit: `security: add Media Hub upload resource guardrails`
