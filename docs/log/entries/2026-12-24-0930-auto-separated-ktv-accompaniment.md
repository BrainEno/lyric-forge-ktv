# [2026-12-24 09:30] Auto-separated KTV accompaniment

- Scope: round 40, next roadmap feature (D-060). The separation that runs before recognition on Windows x64 (D-043) already writes `accompaniment.wav` next to the vocal stem; it was thrown away for KTV.
  - `AutomaticAccompaniment` marker in `AudioAsset.metadata` and `linkAutomaticAccompaniment`: the separated accompaniment becomes the project's `instrumentalPath` unless the user imported one, which is never replaced. Importing an accompaniment drops the marker.
  - The separator links it after a run and on reuse (stems separated before D-060 get linked the next time), keeps the linked run directory when pruning, and with `requireAccompaniment` separates again when the accompaniment file is gone. `ProjectVocalSeparator.supportsCurrentPlatform` is new.
  - `ProjectAccompanimentGenerator`, implemented by `LocalProjectTranscriptionWorkflow`: separation on its own (forced on, whatever the recognition setting), under the recognition lease, on the same progress stream and `cancel`.
  - Project detail → 伴奏与人声: 自动生成伴奏 button (only where the platform can separate and the project has no accompaniment), progress with 停止生成, 换成已有伴奏 label, summary 已有伴奏轨（自动分离）. After recognition or a generation the playing queue gets the new tracks (`updateActiveProjectSources`, which now carries the marker).
  - Player: a separated accompaniment does not start as the default source (the original does); 进入 KTV describes it as separated; the 纯伴奏 unavailable hint mentions automatic generation.
- Files:
  - New: `lib/features/project/domain/models/automatic_accompaniment.dart`, `lib/features/transcription/domain/services/project_accompaniment_generator.dart`, `test/features/project/domain/automatic_accompaniment_test.dart`.
  - Changed: `lib/features/transcription/domain/services/{vocal_separation_planner,project_vocal_separator}.dart`, `lib/features/transcription/data/services/{local_project_vocal_separator,local_project_transcription_workflow}.dart`, `lib/features/project/data/services/file_project_accompaniment_importer.dart`, `lib/features/project/presentation/{screens/project_detail_screen,widgets/project_audio_sources_section}.dart`, `lib/features/player/data/services/default_playback_session_service.dart`, `lib/features/player/domain/models/ktv_backing_mode.dart`, `lib/features/player/presentation/{screens/player_screen,widgets/ktv_entry_sheet}.dart`.
  - Tests: vocal separation planner, separator and workflow tests, `project_audio_sources_section_test.dart`, `project_detail_capability_test.dart`, `ktv_entry_sheet_test.dart`, `project_audio_session_update_test.dart`, `file_project_accompaniment_importer_test.dart`, `documentation_references_contract_test.dart`.
  - `README.md`, `docs/prd.md`, `docs/decisions.md` (D-060), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate.
- Notes:
  - The separated accompaniment can keep traces of the vocal; that is why the player starts on the original and 进入 KTV says so.
- Commit: `Use the separated accompaniment as the project's KTV backing track`
