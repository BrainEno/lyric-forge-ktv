# [2026-11-05 20:24] Avoid text-input overlay in save test

- Scope: Continue verifying P1 #318 editor conflict behavior after CI exposed a Flutter `ListTile`/`ColoredBox` assertion when the selected line Inspector renders its chorus toggle. Invoke Inspector `onChanged` directly, add stage-labeled framework-exception checks, and give `SwitchListTile` a transparent Material boundary to restore visible ink behavior.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; `lib/features/lyrics/presentation/widgets/lyric_inspector_pane.dart`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - Changed Dart files formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - On head `b1630db`, Quality Gate run `42026019494` passed work-log preflight and format check, then failed in the editor conflict test; focused workflow `42026019349` also failed in that test; KTV recovery validation `42026019512` passed.
  - On head `f824167`, Quality Gate run `42026929092` and focused workflow `42026929075` failed in the editor test with the same framework assertion; formatter job and KTV recovery validation `42026929112` passed.
  - Annotation widget shape identifies the Inspector's `SwitchListTile` (rendered as `ListTile` with `onTap`) inside the colored pane; the Material boundary fix and stage checks await pinned CI. Local Flutter/Dart SDKs are unavailable.
- Notes: PR #352 and issue #318 remain open. Retain temporary diagnostic workflow until the corrected editor regression and pinned Quality Gate pass.
- Commit: `fix: isolate inspector switch tile material`
