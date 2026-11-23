# [2026-12-27 10:00] Delete projects and clean up duplicates

- Scope: round 43, user report: some songs have several recognition projects and none can be deleted (D-063).
  - Root cause: nothing in the UI called `ProjectRepository.deleteProject`; `FileBatchTranscriptionQueue` only de-duplicated paths among current queue items, so re-importing a song after clearing finished items created another project.
  - `ProjectDuplicateFinder` (domain): groups projects by canonical audio path, or by normalised title + artist with lengths within 2 s; orders each group keep-first (lyrics, stage, line count, most recent) with `keepReason`.
  - `ProjectDeletionService` (domain) / `LocalProjectDeletionService` (data): refuses while the project is running in the batch queue or is the current playback item; deletes the record, the project's finished/failed queue items and, optionally, `<support>/LyricForge/Projects/<id>` (not an explicit `projectDirectory`, not a folder another project's audio lives in); `check` reports folder size and KTV recordings.
  - UI: `ProjectListScreen` at `Routes.projects` (dashboard 最近工程 → 全部工程): search, duplicate banner with 一键清理重复 and 只看重复的, keep/duplicate badges, per-row menu, multi-select delete. `confirmProjectDeletion` dialog (files checkbox, recordings warning) and `deleteProjectsWithConfirmation` flow shared with the project page's new 更多 → 删除工程 (pops back after deletion). The dashboard refreshes after returning from a project or the list.
  - Queue: before creating a project, `_projectForAudio` reuses an existing project of the same file; one with lyrics is marked complete without recognition (proofread lyrics are never replaced).
- Files:
  - New: `lib/features/project/domain/services/{project_duplicate_finder,project_deletion_service}.dart`, `lib/features/project/data/services/local_project_deletion_service.dart`, `lib/features/project/presentation/project_list_dependencies.dart`, `lib/features/project/presentation/screens/project_list_screen.dart`, `lib/features/project/presentation/widgets/{project_delete_dialog,project_deletion_flow}.dart`.
  - Changed: `lib/features/project/presentation/{project_detail_dependencies.dart,screens/project_detail_screen.dart}`, `lib/features/transcription/data/services/file_batch_transcription_queue.dart`, `lib/features/home/presentation/screens/dashboard_screen.dart`, `lib/core/navigation/{routes,app_destinations}.dart`, `lib/app/{app_router,screen_assembly}.dart`.
  - Tests: `test/features/project/domain/project_duplicate_finder_test.dart`, `test/features/project/data/local_project_deletion_service_test.dart`, `test/features/project/presentation/project_list_screen_test.dart`, `test/features/project/presentation/project_detail_capability_test.dart`, `test/file_batch_transcription_queue_test.dart`, `test/features/home/presentation/screens/dashboard_screen_test.dart`.
  - `docs/decisions.md` (D-063), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate.
- Notes:
  - Deletion cannot be undone; the dialog says the song's audio file is kept.
  - Library songs linked to a deleted project re-resolve on the next play (stale links heal to another project of the same file, or are cleared).
  - Desktop only: phones have no project pages (D-058).
- Commit: `Delete projects and clean up duplicate recognition projects`
