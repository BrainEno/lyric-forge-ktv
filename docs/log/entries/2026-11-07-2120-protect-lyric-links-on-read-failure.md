# [2026-11-07 21:20] Protect lyric links on read failures

- Scope: Fail closed on propagated project, metadata and path resolution read failures, preserving lyric links and cached queue flags; stop unsafe imports and offer a Now Playing retry.
- Files: Playback lyric resolver, local lyric import and Now Playing action, player failure regression tests, index, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42376334233 passed focused player tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks reported separately. git diff --check ran locally.
- Notes: Tests include an invalid file-backed project store, injected read failures, successful stale-link healing, metadata write failure, import failure and retry UI. Reads that storage implementations silently treat as valid or skip cannot be detected here. File repositories cache failed initial loads, so retry may require restart; concurrent metadata changes are not protected by compare-and-swap. No native playback or manual UI checks performed.
- Commit: `fix: preserve lyric links on read failures`
