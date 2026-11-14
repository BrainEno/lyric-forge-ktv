# [2026-11-07 00:01] Preselect and safely reuse project proofreading evidence

- Scope: Make a complete source-hashed single-input ASR pair a default V2 choice only when its primary matches the current draft; keep preview metadata-only and verify project revision, selected audio, and draft during load; share bounded Whisper JSON parsing between recognition and the artifact reader.
- Files: `whisper_json_transcript_parser.dart`, `whisper_json_artifact_reader.dart`, project evidence loader and hint contract, editor dependency assembly/coordinator/options UI, parser/reader/loader/widget/editor/assembly tests, #319 follow-up and V2 plan, work-log index.
- Validation:
  - `git diff --check` => passed.
  - `bash scripts/check_app_identifiers.sh` => passed.
  - `dart format`, `flutter analyze`, targeted Flutter tests, and `dart tool/work_log.dart write/check` => not run: this workspace has no Dart/Flutter/FVM executable; pinned Flutter Quality Gate remains required.
- Notes: The preview returns no transcript rows and does not authorize reuse. Full loading rechecks revision and source-audio hash; a raw Whisper artifact is used only when the parsed language, offset, and every line field match the audio-verified embedded snapshot; absent, failed, or mismatched reads fall back to that snapshot. Non-matching drafts and chunk snapshots remain read-only. #319 is OPEN; its full acceptance audit remains outstanding. No real-song evaluation was run and no recognition-accuracy improvement is claimed.
- Commit: `Add verified project evidence preselection`
