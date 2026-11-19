# [2026-11-19 12:05] Name the import steps

- Scope: UI/UX audit I-01 and I-02. On desktop the import route first opens the recognition environment check, but under the title 批量导入, so people expected a file picker and found a model installer. The gate is now titled 准备识别环境 and both screens show a two-step strip (1 准备识别环境 — 2 选择歌曲) that says where the user is and what comes next. The import hero's three feature pills (逐首处理 / 可暂停 / 恢复 / 进度持久化) became one quiet line, 逐首处理 · 可随时暂停或恢复 · 进度自动保存.
- Files:
  - `lib/features/import/presentation/widgets/import_step_indicator.dart` (new: `ImportStep`, `ImportStepIndicator`).
  - `lib/features/import/presentation/screens/transcription_ready_import_screen.dart` (title, step 1 strip).
  - `lib/features/import/presentation/screens/import_audio_screen.dart` (step 2 strip on desktop via `showSetupSteps`, footnote line instead of `_FeaturePill`).
  - Test: `test/features/import/import_step_indicator_test.dart` (new: current/next/done markers, one semantics summary, narrow width, source checks for the gate title and both strips).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. The import contract strings (`ImportAudioScreen(dependencies: widget.dependencies)`, `if (!_isDesktop)`, `if (readiness?.isReady == true)`) are unchanged.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Mobile import has no preparation step, so `showSetupSteps` defaults to desktop only.
  - The dashboard action is still labelled 批量导入; it leads to the gate, whose step strip now explains the first stop.
- Commit: `Name the import steps`
