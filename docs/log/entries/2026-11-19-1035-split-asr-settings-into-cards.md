# [2026-11-19 10:35] Split the recognition settings into section cards

- Scope: UI/UX audit C-03 and SE-02. The recognition settings were one 1,008-line widget whose single `build` mixed the plan overview, existing-model adoption, storage relocation, install/repair actions and advanced paths inside one card. The state class keeps all logic (contract tests read its source for the install, storage and store wiring), but the UI is now four `SettingsSectionCard`s built by separate methods: "AI / 歌词识别" (overview grid, quality plan, components), "模型与存储" (existing models, storage preflight, relocation), "安装与维护" (progress, errors, install/repair/delete) and "高级设置" (collapsible path summary and the manual editor). The settings page drops its duplicate "设置" heading under the app bar.
- Files:
  - `lib/features/settings/presentation/widgets/settings_section_card.dart` (new: icon, header-semantics title, subtitle, content).
  - `lib/features/settings/presentation/widgets/asr_runtime_overview.dart` (new: `AsrInfoGrid` with `columnsFor`, `AsrInfoTile`, `AsrComponentList`; moved from the section's private widgets). Component states now show Chinese badges ("已安装", "未安装", "安装中", "安装失败", "不可用") instead of the raw enum name.
  - `ai_transcription_settings_section.dart` (1,008 → 895 lines; build split into four card methods), `settings_screen.dart` (no outer card around the section, no duplicate title).
  - Test: `test/features/settings/presentation/widgets/settings_section_widgets_test.dart` (new).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. Every string the settings, install-experience, managed-storage and storage-preflight contract tests look for was checked to remain in the section file. The new files import only core and the transcription domain, so the cross-feature presentation baseline is unchanged.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: four separate cards instead of one; the existing-model and progress cards sit above their buttons instead of after a spacer; the advanced paths are under "查看当前路径" inside the advanced card. The page starts with the one-line description.
  - The setup dialog in the transcription feature keeps its own component list; sharing it would add a cross-feature presentation import.
- Commit: `Split the recognition settings into section cards`
