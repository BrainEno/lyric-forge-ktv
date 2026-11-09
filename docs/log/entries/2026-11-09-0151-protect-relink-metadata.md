# [2026-11-09 01:51] Protect metadata during audio relink

- Scope: Prevent relinking missing audio from losing lyric associations or overwriting existing destination metadata when metadata is incomplete or conflicting.
- Files: FileLocalMediaRelinkService, its real-file integration tests, index, handoff, this entry and generated work-log navigation.
- Validation: Local Flutter/Dart SDKs unavailable. Pinned GitHub Actions run 42506791477 passed focused relink, metadata, play-history and lyric-read tests and the full repository quality gate; Dart format and work-log new/write/check ran there. Final PR checks reported separately. git diff --check ran locally.
- Notes: Relinking checks both paths with authoritative metadata reads before any migration, refuses conflicting existing records and allows a destination record when the old path has none. Tests verify canonical stores, metadata backup, favorites, playlists, history and normal migration. Later I/O failures or concurrent writers can still cause partial migrations; this is not a cross-store transaction. No native picker or manual UI checks performed.
- Commit: `fix: protect metadata during audio relink`
