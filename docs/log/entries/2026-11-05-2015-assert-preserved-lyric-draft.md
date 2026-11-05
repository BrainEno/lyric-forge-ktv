# [2026-11-05 20:15] Assert preserved lyric draft

- Scope: Continue the P1 #318 editor conflict regression fix after CI showed the retained lyric is rendered in more than one widget; assert the inspector controller's draft value directly instead of assuming a unique text node.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - Changed Dart test formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - Pinned Quality Gate run `42025104792` and focused workflow run `42025104761` still failed in the editor test because `Local edit` matched multiple widgets. Formatter and KTV recovery run `42025104807` passed.
  - Quality Gate also reported failure in existing transfer test `total upload deadline applies while chunks continue arriving`; awaiting the next full-suite result to determine whether transient.
  - Local Flutter/Dart SDKs are unavailable; revised test awaits pinned CI.
- Notes: PR #352 and issue #318 remain open; do not merge without explicit authorization. Keep the temporary diagnostics workflow until the corrected regression and pinned Quality Gate pass.
- Commit: `test: assert preserved lyric draft in inspector`
