# [2026-11-05 20:11] Disambiguate lyric editor conflict test

- Scope: Fix the P1 #318 regression test's ambiguous widget tap after CI showed the lyric can appear in both the list and inspector; use the wide-layout inspector field directly and target the save control by its actual button label.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; generated work-log navigation; `docs/handoff.md`.
- Validation:
  - Changed Dart test formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - Pinned Flutter Quality Gate run `42024462741` failed in the conflict test due an ambiguous tap; focused workflow run `42024462874` failed in the same test. Formatter and KTV recovery run `42024463212` passed.
  - Local Flutter/Dart SDKs are unavailable; revised test awaits pinned CI.
- Notes: Keep PR #352 and issue #318 open. Remove `.github/workflows/arena-format-debug.yml` only after the pinned verification succeeds.
- Commit: `test: disambiguate lyric editor conflict test`
