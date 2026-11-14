# [2026-11-14 20:21] Protect local media stores and lyric save exits

- Scope: Resolve #438, #439, and #440 by awaiting lyric persistence before a save-and-leave route exits, retaining dirty drafts after write/conflict failures, and making local library, collections, and metadata repositories reject unsafe snapshots and retry repaired storage in the same instance.
- Files: Lyric editor screen/content; local media library, collection, and metadata repositories; save-and-leave widget tests; real-file local-media recovery tests; generated work-log navigation and handoff.
- Validation:
  - `git diff --check` => passed.
  - `bash scripts/check_app_identifiers.sh` => passed.
  - Changed Dart files formatted and syntax-checked with `@wasm-fmt/dart_fmt@0.4.0` => passed.
  - GitHub Actions Flutter Quality Gate `43594895717` => passed: work-log preflight, changed-file format check, analysis, vendored backend tests, and the complete repository quality gate all ran on the pinned Flutter toolchain.
  - GitHub Actions KTV history and recovery validation `43594895721` => passed.
  - Local `flutter`/`dart`/`fvm` commands remain unavailable in the sandbox.
- Notes: Library and collections now fail closed for malformed or duplicate rows instead of presenting a writable subset; metadata retains its documented best-effort display reads but re-parses incomplete snapshots before a later authoritative read or write. This does not add cross-process compare-and-swap, a file lock, or physical-device validation.
- Commit: `fix: preserve local media and lyric drafts`
