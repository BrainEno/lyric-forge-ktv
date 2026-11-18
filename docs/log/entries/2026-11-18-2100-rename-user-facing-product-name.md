# [2026-11-18 21:00] Rename the user-facing product name to LyricForge KTV

- Scope: UI/UX audit B-02 (P1). The window title, dashboard heading, settings subtitle, diagnostics bundle, system media session, notification channel, permission prompts and several setup/recognition hints still said "Elysium Player" while the product is LyricForge KTV. Every user-visible occurrence now says LyricForge KTV. Identifiers that decide where user data lives are deliberately unchanged (D-029).
- Files:
  - Dart UI/text: `lib/app/app.dart`, `lib/core/diagnostics/app_build_info.dart`, `dashboard_screen.dart`, `transcription_ready_import_screen.dart`, `project_detail_screen.dart` (the empty-metadata subtitle becomes 本地音频 · LyricForge KTV 工程 instead of a doubled "KTV KTV"), `settings_screen.dart`, `ai_transcription_settings_section.dart`, `asr_existing_model_actions.dart`, `asr_runtime_setup_dialog.dart`, `media_hub_connection.dart` (pairing error text).
  - Platform media/permission text: `desktop_audio_backend.dart`, `mobile_system_media_session.dart`, `record_soloud_ktv_microphone_service.dart`.
  - Platform display labels: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `windows/runner/main.cpp`, `linux/runner/my_application.cc` (was the template default `lyric_forge_ktv`).
  - Tests: `test/widget_test.dart`, `test/core/diagnostics/diagnostics_report_test.dart`.
  - Docs: `docs/decisions.md` (D-029), this entry, generated work-log files.
- Validation:
  - The sandbox has no Dart/Flutter toolchain (storage.googleapis.com and pub.dev are blocked). `dart format` ran on GitHub Actions through a temporary branch-only probe workflow (removed before review); it reported pre-existing tall-style churn in `mobile_system_media_session.dart` and `record_soloud_ktv_microphone_service.dart`, applied here as one-time formatting. `flutter analyze` and the full test suite run in the PR's Flutter Quality Gate.
  - `rg "Elysium Player"` outside docs/artifacts => only `Runner.rc`, `AppInfo.xcconfig` and the macOS workflow artifact paths remain, as intended.
  - Work-log `write` + `check` => reproduced with a line-by-line Python port of `tool/work_log.dart` (verified to regenerate the baseline with zero diff); the CI preflight re-runs the Dart tool.
- Notes:
  - Windows file properties/Task Manager and the macOS `.app` bundle still show Elysium Player until a data-directory migration exists (D-029).
  - The Dart class `ElysiumPlayerApp` and the doc comment in `system_media_audio_handler.dart` keep the old name; neither is user-visible.
- Commit: `Rename user-facing product name to LyricForge KTV`
