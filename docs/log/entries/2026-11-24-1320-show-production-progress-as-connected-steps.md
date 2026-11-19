# [2026-11-24 13:20] Show production progress as connected steps

- Scope: UI/UX audit P-01 (five kinds of pill on the project page). The status, metadata and metric pills already go through `AppBadge`; the last one, `_StagePill` in the 制作进度 card, looked like those badges although it is a sequence, gave done and running steps the same look, and on phones scrolled sideways. It is replaced by `ProductionSteps`: five icons in circles on a connecting line with the labels underneath, done steps filled with a check, the current step outlined, all five fitting a 296 px card without scrolling. `productionStepsFor` derives the states from the processing stage: passed steps are done, a running recognition is 进行中 and is the only current step, otherwise the first open step is 下一步. Each step reads as 第 N 步，共 5 步：label，state.
- Files:
  - `lib/features/project/presentation/widgets/production_steps.dart` (new: `ProductionStepState`, `ProductionStep`, `productionStepsFor`, `ProductionSteps`).
  - `lib/features/project/presentation/screens/project_detail_screen.dart` (`_ProcessingProgress` uses `ProductionSteps`; `_StagePill` and the compact horizontal scroll removed).
  - Test: `test/features/project/presentation/production_steps_test.dart` (new: order and labels, states for each stage, vocal separation, exported, running and rerun recognition, state words, fits a phone card without scrolling, check icons, step semantics).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The thresholds per step are unchanged (导入 at `audioImported`, 音频处理 at `audioNormalized`, 歌词识别 at `transcriptionComplete`, 歌词校对 at `lyricsEdited`, 导出 at `exported`).
  - Done steps use black icons on the accent fill (8.1:1).
- Commit: `Show production progress as connected steps`
