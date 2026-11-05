# [2026-11-05 17:45] Move ForcedAligner language guidance to presentation

- Scope: Replace the unsupported-project-language free-form error in `ForcedAlignmentLanguage` with a typed exception carrying the original language. Map the existing Chinese troubleshooting guidance in presentation and preserve the editor's full error message.
- Files: `lib/features/lyrics/domain/proofreading/forced_alignment_language.dart`, `lib/features/lyrics/presentation/lyric_review_strings.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, language resolver and presentation string tests, this entry, generated work-log navigation, and `docs/handoff.md`.
- Validation:
  - `git diff --check` => passed.
  - Temporary WASM `@wasm-fmt/dart_fmt` formatter check => passed for changed Dart files.
  - Local Flutter/Dart analyzer and tests => not run because the pinned SDK is unavailable in this workspace.
  - Pinned Flutter Quality Gate run `42004606274` => passed on implementation head `55ceb4dddb82c3a48ce2d560ba85f67ca488fbd9`, including work-log preflight, changed-Dart format, analysis, and full tests.
  - Documentation-updated PR-head run `42005165752` => failed at unrelated test `test/features/transfer/http_media_hub_upload_test.dart: total upload deadline applies while chunks continue arriving`; work-log preflight and changed-Dart format passed.
  - Follow-up PR-head run `42005686105` => passed on head `022afc1e6563bcfbdeea0fa4ef6039af7bd562e0`, including work-log preflight, changed-Dart format, analysis, and full tests. Recheck the gate if the PR head changes again.
- Notes: PR #350 is open for review and is not authorized for merge. Resolver tests now assert typed failure data; presentation tests assert the exact existing guidance. Native, KTV recovery, runtime-release, icon, and other specialist workflows were not audited.
- Commit: `refactor: move ForcedAligner language guidance to presentation`
