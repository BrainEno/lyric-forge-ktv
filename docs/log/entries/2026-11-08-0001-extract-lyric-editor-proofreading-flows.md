# [2026-11-08 00:01] Extract lyric editor proofreading flows

- Scope: Move the editor body and three proofreading interaction flows out of LyricEditorScreen while keeping domain proposal rules and editor state ownership unchanged.
- Files: lyric_editor_screen.dart, lyric_editor_content.dart, lyric_editor_proofreading_coordinator.dart, lyric_editor_orchestration_contract_test.dart, app_assembly_contract_test.dart, lyric_proofreading_ux_review.md, handoff and generated work-log navigation.
- Validation:
  - dart format changed Dart files => passed in the pinned Flutter Actions run.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed; info-level diagnostics are permitted by the repository gate.
  - Focused V2, reference, editor, integration, dialog and orchestration contract tests => passed.
- Notes: Screen is below 1200 lines and all three entry methods remain below 40 lines; proposal decisions remain in domain use cases. Physical-device, real-audio and screen-reader behavior were not tested.
- Commit: `Extract lyric editor proofreading flows`
