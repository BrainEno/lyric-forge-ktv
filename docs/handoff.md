# Handoff

## 目标
Build dependable open-source, local-first KTV software with safe persistence/recovery, high-quality local ASR, and reliable editing/playback workflows.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: 00c8aef7beb535e13541a1865e54f1af187109a1
- Branch: fix/json-persistence-recovery-20261028
- PR: pending creation for shared recoverable JSON persistence.
- Scope: add a shared recoverable JSON replacement helper and migrate the file-backed stores that previously deleted canonical files before renaming temporary files.
- Local Dart/Flutter SDKs are unavailable in this environment; GitHub Actions is the validation gate.

## 已改文件
- lib/core/persistence/atomic_json_file.dart
- test/core/persistence/atomic_json_file_test.dart
- test/file_project_repository_test.dart
- lib/features/project/data/repositories/file_project_repository.dart
- lib/features/transcription/data/services/file_batch_transcription_queue.dart
- lib/features/player/data/repositories/file_local_media_library_repository.dart
- lib/features/player/data/repositories/file_local_media_collection_repository.dart
- lib/features/player/data/repositories/file_local_media_metadata_repository.dart
- lib/features/player/data/repositories/file_play_history_repository.dart
- lib/features/player/data/repositories/file_playback_session_store.dart
- lib/features/transfer/data/services/file_media_hub_connection_store.dart
- lib/features/transfer/data/services/file_media_hub_device_identity_store.dart
- lib/features/transfer/data/services/file_media_transfer_queue_service.dart
- docs/engineering_risks_roadmap.md
- docs/work_log_index.md
- docs/work_log.md
- docs/work_log_archive.md
- docs/log/entries/2026-10-28-1640-recoverable-json-persistence.md
- docs/handoff.md

## 本轮实现
- Added `AtomicJsonFile` with JSON/schema validation, flush-before-replacement, a previous-generation backup, rollback on replacement failure, and startup recovery from valid temporary/backup candidates.
- Migrated project persistence, batch transcription queue, local media library/collections/metadata, play history, playback session, Media Hub connection/device identity, and Media Hub transfer queue.
- Explicitly remove recovery sidecars when clearing saved Media Hub connection or playback session state, avoiding restoration of intentionally cleared state.
- Added fault-injection unit tests and a project-store integration regression.
- Updated the product-quality roadmap and work-log navigation.

## 检查结果
- Code has been pushed to the feature branch; final PR-head formatting, analyzer, and regression results must be checked in GitHub Actions.
- Local Dart/Flutter checks were not run because the SDKs are unavailable in this environment.
- The recovery protocol keeps one previous valid generation; it is not a database-grade transaction and does not claim tested power-loss durability across all filesystems.

## 下一步
1. Review the complete PR diff and fix any formatting, analysis, or regression failures.
2. Confirm CI covers replacement failure after canonical removal, temporary/backup recovery, and refusing to overwrite an unrecoverable malformed store.
3. Follow up with Windows/macOS fault-injection validation and ASR CLI timeout/cancellation lifecycle hardening.

## 已知风险
- If the canonical file and all sidecars are corrupted, manual recovery may still be required.
- Validators check each store's top-level data shape; existing per-row decoding rules remain.
- Cross-platform replacement/durability semantics must be verified before claiming filesystem-level atomicity.

最后更新：2026-10-28 16:40（Asia/Taipei）
