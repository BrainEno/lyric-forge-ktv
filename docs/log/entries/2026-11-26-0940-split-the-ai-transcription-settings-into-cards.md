# [2026-11-26 09:40] Split the AI transcription settings into cards

- Scope: UI/UX audit SE-04 (P2). `AiTranscriptionSettingsSection` was one ~900-line stateful widget. It held the services, the install, pause, resume, move and delete flows with their dialogs, and the four cards with nested ternaries for the status and button labels. The cards are now stateless widgets in `ai_transcription_settings_cards.dart`: `AsrPlanCard`, `AsrStorageSettingsCard`, `AsrMaintenanceCard` and `AsrAdvancedSettingsCard`. Each takes plain values and callbacks, and an action is null when the section is busy. The wording lives in pure `AsrSettingsText` functions: component, mode and model labels, byte sizes, install state, install-button label, move progress and configured paths. The section keeps the state and flows and is down to about 600 lines. One visible change: 查看当前路径 used to show one six-line string, and now lists each path under its own label as selectable text, so long paths wrap under their label. The new widget tests also caught a framework assertion: the 查看当前路径 tile sat on the card's painted background, which hid its ink. A transparent `Material` around it fixes that.
- Files:
  - `lib/features/settings/presentation/widgets/ai_transcription_settings_cards.dart` (new).
  - `lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart` (build delegates to the cards; label helpers removed).
  - `test/features/settings/presentation/widgets/ai_transcription_settings_cards_test.dart` (new: wording functions; plan card ready colour, detection state and mode change; storage card existing-model and restore-default rules; maintenance card install, refresh, delete, busy, no space, pause, resume and failed-component retry; advanced card path rows and disabled editor).
  - `test/architecture/support/feature_dependency_baseline.dart`: the three transcription widget imports (error, progress and storage cards) moved from the section to the cards file, which also imports the existing-model card the section still needs for its path dialog. Net +1 edge, from the new file.
  - The source contract tests (`transcription_settings_contract_test.dart`, `asr_install_experience_contract_test.dart`, `asr_managed_storage_contract_test.dart`, `asr_storage_preflight_contract_test.dart`) now read the section and its cards together.
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Behaviour kept: busy rules, the 空间不足 block, the retry label naming the failed component, and the existing-model card hiding once the runtime is ready unless a scan message is showing.
  - Not checked in a running app.
- Commit: `Split the AI transcription settings into cards`
