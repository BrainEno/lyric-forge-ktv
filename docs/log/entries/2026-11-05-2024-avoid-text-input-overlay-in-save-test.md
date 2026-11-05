# [2026-11-05 20:24] Avoid text-input overlay in save test

- Scope: Continue verifying P1 #318 editor conflict behavior after CI failed in the widget test with a Flutter framework `ListTile`/`ColoredBox` assertion; trigger the Inspector field's `onChanged` callback directly to avoid opening a text-input toolbar while retaining the editor update path.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - Changed Dart test formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - On head `b1630db`, Quality Gate run `42026019494` passed work-log preflight and format check, then failed in the editor conflict test; focused workflow `42026019349` and formatter failed in the same test/job, formatter subjob passed; KTV recovery validation `42026019512` passed.
  - Failure annotations expose a Flutter framework `ListTile`/`ColoredBox` assertion but not the exact widget interaction; new test version awaits pinned CI.
  - Local Flutter/Dart SDKs are unavailable.
- Notes: PR #352 and issue #318 remain open. Retain temporary diagnostic workflow until the corrected editor regression and pinned Quality Gate pass.
- Commit: `test: exercise lyric edits through inspector callback`
