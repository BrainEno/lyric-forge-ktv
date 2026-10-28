# [2026-10-28 22:15] Pin and verify managed FFmpeg downloads

- Scope: Fix issue #217 by removing floating FFmpeg URLs, verifying release-pinned SHA-256 digests before extraction, and preserving the previous installation until the replacement executable is validated.
- Files: `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, `lib/features/transcription/data/services/ffmpeg_runtime_release.dart`, `lib/features/transcription/data/services/runtime_sha256.dart`, `test/runtime_integrity_install_contract_test.dart`, `test/ffmpeg_runtime_release_test.dart`, `test/runtime_sha256_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-2215-pin-and-verify-managed-ffmpeg.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`.
- Validation:
  - Release asset URLs, names, and SHA-256 values were checked against the upstream GitHub release API.
  - Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.
  - GitHub Actions on the final PR head must pass before this issue is considered complete.
- Notes: The installer now pins Windows x64 to a versioned BtbN LGPL build and macOS/Linux x64/arm64 to v9.0.2 release assets. It hashes the archive before extraction, rejects and deletes mismatches, validates the staged executable, and rolls back if directory activation fails. No claim is made about real-device runtime validation yet.
- Commit: `fix: pin and verify managed FFmpeg downloads`
