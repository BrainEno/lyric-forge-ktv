# [2026-12-02 09:30] Move the recognition settings flows out, pass the editor groups to the panes

- Scope: Two follow-ups from round 14. C-03: 设置 → 本地识别 was still one State object of about 590 lines after its cards moved out; it held the four services, eighteen fields of progress and error state, and the install, pause, existing-model, storage-move and delete flows. Those flows are now `AiTranscriptionSettingsController` (a `ChangeNotifier` that only talks to the domain services and checks `isDisposed` after every await). The section keeps what needs a `BuildContext` (confirmation dialogs, the folder picker, the path dialog, the advanced dialog, the snack bar after a move) and the layout of the four cards; it went from about 590 to about 240 lines. The texts of the existing-model flow come from `AsrFolderText` through `AsrExistingModelTexts`, so the controller does not import the transcription presentation layer. E-04: `LyricEditorToolbar`, `LyricListPane` and `InspectorPane` now take `LyricReviewControls` and `LyricPlaybackControls` directly instead of unpacked values; the list works out the selection, the filter and 显示全部歌词 from the review group, and the inspector works out the review switch, the playhead row and seeking (plus the offset) from both groups. The content no longer unpacks them or keeps its own `_decide` helper.
- Files:
  - New: `lib/features/settings/presentation/widgets/ai_transcription_settings_controller.dart`, `test/features/settings/presentation/widgets/ai_transcription_settings_controller_test.dart`, `test/features/lyrics/presentation/widgets/lyric_editor_panes_controls_test.dart`.
  - `lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart`.
  - `test/features/settings/transcription_settings_contract_test.dart`, `test/features/transcription/asr_install_experience_contract_test.dart`, `test/features/transcription/asr_managed_storage_contract_test.dart`, `test/features/transcription/asr_storage_preflight_contract_test.dart` (the source contracts now read the controller too).
  - `lib/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart`, `lyric_list_pane.dart`, `lyric_inspector_pane.dart`, `lyric_editor_content.dart`, `lyric_editor_review_controls.dart`.
  - `test/features/lyrics/presentation/widgets/lyric_editor_toolbar_test.dart`, `lyric_list_pane_test.dart`, `lyric_line_structure_widgets_test.dart`.
- Validation:
  - The controller test covers loading, plan changes, insufficient space, install, pause and resume, failures, existing models, storage moves, deleting and the messages, with fake services.
  - The panes test pins what the list and the inspector now derive from the groups; the toolbar test covers both groups.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - The list's 显示全部歌词 action is now derived: present whenever a filter other than 全部 is on.
  - The editor's filter, start-review, follow-playback and split behaviour were not checked on a device.
- Commit: `Move the recognition settings flows into a controller`
