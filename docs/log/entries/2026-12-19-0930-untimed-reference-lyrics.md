# [2026-12-19 09:30] Untimed reference lyrics

- Scope: round 32. The user asked for lyrics for songs without a lyric project: fetch timed lyrics that match the song when possible, let the user see whether the timing lines up, offer to strip the timestamps and keep plain text when it does not, also accept plain text directly, and show untimed lyrics in the player as static text the user scrolls by hand. Changes (D-054):
  - Domain: `LyricDocumentTiming` / `ProjectLyricTiming` extensions (`isUntimed`, `isTimed`, `withoutTimestamps`, `activeLineIndex`, `effectiveStart`, `lastTimedStart`, `hasTimedLyrics`, `hasUntimedLyrics`). Untimed means no line has any time; the import-time `timed:false` flag is ignored because it goes stale once the user taps timing.
  - `SongLyricsLookup` searches LRCLIB, NetEase and Kugou through the existing `OnlineLyricSearchService`, sanitizes credits, parses with the app's LRC parser, ranks by title, artist, length and timing, collapses identical lyrics, and pairs every timed option with a plain twin. Helpers for provenance, untimed/shifted/script-converted import results.
  - UI: lyric source sheet (联网获取 / 导入文件 / 粘贴), the online preview dialog (re-search, version picker, live highlight while the song plays, follow scrolling, tap a line to seek, ±0.5 s shift, 简体/繁體, length-mismatch warning, 采用（带时间轴） / 只用文字（去掉时间戳）), the paste dialog (format detection, optional timestamp stripping).
  - Local song 导入歌词 now asks for the source first; online and pasted lyrics open the project player, timed files still open the editor, plain-text files open the player.
  - Project player: untimed lyrics render as 参考歌词（无时间轴） (static, manual scrolling, no highlight, no seek, no times) with 去打轴 / 联网找带时间轴的歌词; KTV entry, mode chip and fullscreen are disabled; the empty state offers 联网获取歌词 / 粘贴歌词 / 导入歌词文件. The fullscreen KTV stage explains untimed lyrics instead of freezing on line one.
- Files:
  - New: `lib/features/project/domain/models/lyric_timing.dart`, `lib/features/lyrics/domain/online/song_lyrics_lookup.dart`, `lib/features/player/presentation/widgets/{song_lyrics_preview_dialog,paste_lyrics_dialog,lyrics_source_sheet,reference_lyrics_view,song_lyrics_acquisition}.dart`.
  - Changed: `lib/features/player/presentation/{local_library_dependencies,playback_screen_dependencies}.dart`, `presentation/screens/player_screen.dart`, `presentation/widgets/{local_song_lyrics_import_action,project_player_transport,fullscreen_ktv_lyric_stage}.dart`, `lib/app/{lyric_editor_assembly,local_library_assembly,playback_assembly}.dart`.
  - Tests: `test/features/project/lyric_timing_test.dart`, `test/features/lyrics/domain/online/song_lyrics_lookup_test.dart`, `test/features/player/presentation/widgets/{song_lyrics_preview_dialog,paste_lyrics_dialog}_test.dart`, `test/features/player/player_reference_lyrics_test.dart`.
  - `docs/decisions.md` (D-054), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - The timing preview needs the song to play in the app player; from the library it offers 播放这首歌来核对 when another song is playing.
  - Only title, artist and length are sent to the lyric sites, as with 一键校对.
- Commit: `Add untimed reference lyrics`
