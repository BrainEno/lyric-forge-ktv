# [2027-01-06 10:00] Move the editor's save and audition out of the screen

- Scope: round 53, the next round after the listen home split: the lyric editor screen was at 1198 of the 1199 lines `lyric_editor_orchestration_contract_test` allows (D-073). No visible change.
  - `controllers/lyric_editor_save_flow.dart`: `LyricEditorSaveFlow` owns `projectRevision` and the in-flight save. `save(project)` shares a running save, writes with `updateProjectIfUnchanged`, and on `ProjectUpdateConflictException` runs the conflict dialog (keep editing / reload latest / overwrite, retrying on a newer conflict). Messages are unchanged. The screen passes `onProjectChanged` (swap in the completed project future) and `onSavingChanged` (rebuild for the save button).
  - `controllers/lyric_editor_audition_flow.dart`: `LyricEditorAuditionFlow` with `previewLine`, `previewTimedLine`, `previewToken`, `togglePlayback(selectedLineIndex:)` and `seek`. The three copies of the duration-and-window calculation became `windowFor`, with the pure `audioDurationFor` (player duration while it plays this project, else the stored one) and `playbackItemFor` (vocal stem first).
  - `lyric_editor_screen.dart`: 1198 → 783 lines. The `LyricEditorProofreadFlowHost` previews now forward to the audition flow; the snackbar helper `_showMessage` backs the flow's messages.
- Files:
  - New: `lib/features/lyrics/presentation/controllers/{lyric_editor_save_flow,lyric_editor_audition_flow}.dart`, `test/features/lyrics/presentation/controllers/lyric_editor_audition_flow_test.dart` (5 tests).
  - Changed: `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `docs/lyric_review_alignment_plan.md` (stale method name).
  - `docs/decisions.md` (D-073), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox; a temporary branch CI probe ran `dart format`, `flutter analyze` and `flutter test`.
  - Probe results: see handoff.
- Notes:
  - The editor's existing widget tests (save, save conflict, audition, proofreading previews) are unchanged and act as the regression check.
  - Built on the same branch as round 52 (PR #520 not yet merged), so the PR now carries both rounds.
- Commit: `Move the lyric editor's save and audition out of the screen`
