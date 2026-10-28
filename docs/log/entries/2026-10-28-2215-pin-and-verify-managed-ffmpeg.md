# [2026-10-28 22:15] Pin and verify managed FFmpeg downloads

- Scope: Fix issue #217 by removing floating FFmpeg URLs, verifying release-pinned SHA-256 digests before extraction, and preserving the previous installation until the replacement executable is validated.
- Files: `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`, `lib/features/transcription/data/services/ffmpeg_runtime_release.dart`, `lib/features/transcription/data/services/runtime_sha256.dart`, `test/runtime_integrity_install_contract_test.dart`, `test/ffmpeg_runtime_release_test.dart`, `test/runtime_sha256_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-2215-pin-and-verify-managed-ffmpeg.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`.
- Validation:
  - Confirmed the pinned asset URLs, filenames, and SHA-256 digests against upstream GitHub release asset metadata.
  - Code/test head `dc53fca810663679fd2bb6e56e3ef4ecdd9b518e` passed all six relevant GitHub Actions workflows:
    - [Flutter Quality Gate](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648450) — **784 tests passed**, formatter, analysis and work-log checks passed.
    - [Runtime integrity validation](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648477) — **784 tests passed**.
    - [ASR managed storage location validation](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648171) — **784 tests passed**.
    - [ASR install experience validation](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648164) — **784 tests passed**.
    - [Transcription settings validation](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648326) — **784 tests passed**.
    - [ASR client checks](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40710648540) — passed.
  - The initial failures were genuine formatter and test-scope defects; both were corrected without skipping checks or weakening assertions.
  - Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.
- Notes: The installer now pins Windows x64 to a versioned BtbN LGPL build and macOS/Linux x64/arm64 to v9.0.2 release assets. It hashes the archive before extraction, rejects and deletes mismatches, validates the staged executable, and rolls back if directory activation fails. No claim is made about real-device runtime validation yet. Recovery now validates an activated FFmpeg executable before discarding a backup left by an interrupted directory swap.
- Commit: `fix: pin and verify managed FFmpeg downloads`
