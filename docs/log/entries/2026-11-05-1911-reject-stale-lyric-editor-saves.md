# [2026-11-05 19:11] Reject stale lyric editor saves

- Scope: Address the data-loss path in P1 issue #318 by adding persisted project revisions and conditional updates, then make the lyric editor reject stale saves and offer explicit keep/reload/overwrite resolution.
- Files: `lib/features/project/domain/models/project_manifest.dart`; `lib/features/project/domain/repositories/project_repository.dart`; file and memory project repositories; `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`; new project-save-conflict dialog; repository and editor regression tests; generated work-log navigation.
- Validation:
  - `git diff --check` => passed.
  - Changed Dart files formatted with `@wasm-fmt/dart_fmt@0.4.0`; pinned Flutter Quality Gate pending.
  - Local Flutter/Dart SDKs are unavailable.
- Notes: Existing manifests without a revision load as revision zero. Repository updates increment the revision; conditional writes compare and replace before yielding. Editor overwrite is an explicit choice and is based on the current conflicting project so its newer metadata is preserved.
- Commit: `fix: reject stale lyric editor saves`
