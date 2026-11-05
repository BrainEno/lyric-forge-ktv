# [2026-11-05 20:24] Avoid text-input overlay in save test

- Scope: Continue verifying P1 #318 editor conflict behavior after CI failed in the widget test with a Flutter framework `ListTile`/`ColoredBox` assertion; invoke Inspector `onChanged` directly and add stage-labeled framework-exception checks to pinpoint the interaction without text-input overlays.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - Changed Dart test formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - On head `b1630db`, Quality Gate run `42026019494` passed work-log preflight and format check, then failed in the editor conflict test; focused workflow `42026019349` also failed in that test, formatter subjob passed; KTV recovery validation `42026019512` passed.
  - On head `f824167`, Quality Gate run `42026929092` and focused workflow `42026929075` failed in the editor test with the same Flutter `ListTile`/`ColoredBox` assertion; formatter job and KTV recovery validation `42026929112` passed.
  - Failure annotations did not identify the exact test phase. New stage-labeled exception checks await pinned CI; local Flutter/Dart SDKs are unavailable.
- Notes: PR #352 and issue #318 remain open. Retain temporary diagnostic workflow until the corrected editor regression and pinned Quality Gate pass.
- Commit: `test: capture editor test framework exception`
