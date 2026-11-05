# [2026-11-05 20:24] Avoid text-input overlay in save test

- Scope: Continue verifying P1 #318 editor conflict behavior after CI exposed a Flutter `ListTile`/`ColoredBox` assertion when the selected line Inspector renders its chorus toggle. Invoke Inspector `onChanged` directly, add stage-labeled framework-exception checks, and give `SwitchListTile` a transparent Material boundary to restore visible ink behavior.
- Files: `test/features/lyrics/presentation/screens/lyric_editor_save_conflict_test.dart`; `lib/features/lyrics/presentation/widgets/lyric_inspector_pane.dart`; generated work-log navigation; `docs/handoff.md`; temporary diagnostics workflow (removed after validation).
- Validation:
  - Changed Dart files formatted with `@wasm-fmt/dart_fmt@0.4.0`; `git diff --check` => passed.
  - Earlier CI heads `b1630db` and `f824167` failed in the editor conflict test with a Flutter `ListTile`/`ColoredBox` assertion; KTV recovery validation passed on both.
  - On code head `89305b9`, pinned Flutter Quality Gate run `42028103622` passed, including work-log preflight, format, analyze, and full repository tests. Focused `project-save-tests` and formatter jobs in run `42028103428` passed; KTV recovery validation run `42028103636` passed.
  - Inspector's SwitchListTile now has an explicit transparent Material ancestor. Local Flutter/Dart SDKs are unavailable.
- Notes: Temporary `.github/workflows/arena-format-debug.yml` removed after focused tests and formatter passed. Cleanup head `ec0422a` passed pinned Flutter Quality Gate run `42028687449` and KTV recovery run `42028687477`. A later docs-only head `d72ae42` hit the intermittent unrelated Media Hub `total upload deadline applies while chunks continue arriving` failure in run `42029196286`; KTV validation `42029196309` passed. Subsequent head `e21ddfe` passed pinned Flutter Quality Gate `42029849324` and KTV recovery validation `42029849242`. PR #352 and issue #318 remain open.
- Commit: `fix: isolate inspector switch tile material`
