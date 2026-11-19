# [2026-11-29 09:30] Let the library take back paired lyrics

- Scope: Follow-up suggested in the round 11 handoff, decision D-034. Lyrics paired from a file name (D-033) were indistinguishable from lyrics the user chose, and a wrong guess could only be removed by deleting the project, after which the next pass paired it again. Each automatic pairing now leaves a `LibraryLyricsPairing` record (`lyricAutoLink`) in the song's local metadata: file, project, reason, whether the project was created, the saved revision, the previous status and stage, and a fingerprint of the lyric lines. The library labels such songs 自动配对歌词, shows a 自动配对 smart view while any exist, and offers 解除自动配对 in the song menu. `LibraryLyricsAutoLinker.unpair` keeps lyrics edited since the pairing (fingerprint differs), deletes a project it created that was never saved again, otherwise empties the project and restores its earlier status and stage; it unlinks the song, marks queued copies as without lyrics and remembers the file in `lyricAutoLinkDismissed` so later passes skip it for that song. The notice can undo through `pairAgain`. Linking a song by hand drops a stale record.
- Files:
  - `lib/features/player/domain/services/library_lyrics_pairing.dart` (new: record, `lyricLinesFingerprint`, `projectWithoutPairedLyrics`).
  - `lib/features/player/domain/services/library_lyrics_auto_linker.dart` (record on attach, dismissed files, `unpair`, `pairAgain`), `playback_lyrics_project_linker.dart` (`pairing` parameter; drops stale records).
  - `lib/features/player/domain/models/local_library_browse_item.dart` (`autoPairedLyrics` view, `hasAutoPairedLyrics`; touched lines reformatted to the current formatter).
  - `lib/features/player/presentation/widgets/library_lyrics_unpair_action.dart` (new: dialog and notice with undo), `library_lyrics_link_text.dart` (reasons, question, outcomes), `screens/local_library_explorer_screen.dart` (label, smart view chip, menu item).
  - Tests: `test/features/player/domain/services/library_lyrics_pairing_test.dart`, `test/features/player/domain/models/local_library_auto_paired_view_test.dart`, `test/features/player/presentation/widgets/library_lyrics_unpair_action_test.dart` (new); `library_lyrics_auto_linker_test.dart`, `library_lyrics_link_text_test.dart` (extended).
  - `docs/decisions.md` (D-034).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; format, analyze and tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The fingerprint covers line text and timing only, so saving review marks or other project details does not make unchanged lyrics count as edited; such a project is emptied rather than deleted.
  - Dismissal is per song and per file: a different file can still be paired with the song, and the same file with another song.
  - Not tried in a running app.
- Commit: `Let the library take back paired lyrics`
