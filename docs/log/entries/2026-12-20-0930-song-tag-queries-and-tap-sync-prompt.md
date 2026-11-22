# [2026-12-20 09:30] Song tag queries and tap-sync prompt

- Scope: round 33, the follow-ups from the round 32 handoff (D-055):
  - Online lyric queries fall back to the audio file's tags. `OnlineLyricQuery.candidatesFor` orders the project-name query first unless the name is a placeholder (`isPlaceholderName`: digits/dates, recorder defaults, camera/chat file names, hashes), then the tag title; a missing artist comes from the tags, duplicates are dropped. `readSongTagsSafely` gives up after 3 s and turns every failure into null; `readAudioFileSongTags` reads tags without decoding artwork.
  - 一键校对 (`LyricAutoProofreadFlow`), the local song 联网获取歌词 action and the project player's 联网获取歌词 try the candidates in turn before asking the user; a manual retry stops the automatic fallback. The preview dialog shows the query that found results.
  - Lyric editor: untimed documents show a 歌词还没有时间轴 card with 开始打轴 (tap sync) instead of the recognition summary; disabled without audio.
  - Now Playing: untimed lyric projects offer 参考歌词, a bottom sheet with the static reference view and 去打轴.
- Files:
  - New: `lib/features/lyrics/domain/online/song_tags.dart`, `lib/features/lyrics/data/services/audio_file_song_tag_reader.dart`, `lib/features/lyrics/presentation/widgets/lyric_tap_sync_prompt_card.dart`.
  - Changed: `lib/features/lyrics/domain/online/online_lyric_query.dart`, `lib/features/lyrics/presentation/{lyric_editor_dependencies,controllers/lyric_auto_proofread_flow,controllers/lyric_editor_proofreading_coordinator,widgets/lyric_editor_content}.dart`, `lib/features/player/presentation/{local_library_dependencies,playback_screen_dependencies,screens/player_screen}.dart`, `lib/features/player/presentation/widgets/{song_lyrics_acquisition,song_lyrics_preview_dialog,local_song_lyrics_import_action,now_playing_lyrics_project_action}.dart`, `lib/app/{lyric_editor_assembly,local_library_assembly,playback_assembly}.dart`.
  - Tests: `test/features/lyrics/domain/online/song_tags_test.dart`, `test/features/lyrics/presentation/widgets/lyric_tap_sync_prompt_card_test.dart`, `test/features/player/presentation/widgets/song_lyrics_preview_dialog_test.dart`, `test/features/player/playback_lyrics_read_failure_test.dart`.
  - `docs/decisions.md` (D-055), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Tags are a second opinion only; a name the user typed is always searched first unless it looks like a recording's default name.
  - A digits-only song title ("1979") counts as a placeholder but is still searched, after the tags.
- Commit: `Add song tag queries and tap-sync prompt`
