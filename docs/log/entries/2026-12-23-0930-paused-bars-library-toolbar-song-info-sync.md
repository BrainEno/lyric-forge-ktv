# [2026-12-23 09:30] Paused bars, library toolbar and song info sync

- Scope: round 38, three issues the user reported after round 37 (D-059):
  - Playback state: just_audio keeps `playing` true after the queue ends, so the rhythm bars, the record and the pause icon kept "playing"; `JustAudioPlayerService.reportsPlaying` treats a completed song as stopped and `play()` restarts a finished song. just_audio's `play()` only completes on pause, so every `await play()` in the session (library reload after a tap, play history, opening Now Playing from the phone's lyrics page) waited for the next pause; `untilStarted` returns once playback starts or fails. Paused rhythm bars drop to a low, level, faded row instead of a frozen frame of the bounce.
  - Music library: new `LibraryExplorerHeader` — search; one 48 dp toolbar (violet 播放全部 / 播放结果, 随机播放, sort menu, grid/list toggle, the phone's library menu); smaller filter chips without icons; one quiet counts line. The phone loses the duplicate 音乐库 app bar; rows get a little more space.
  - Song info: `applySongInfoUpdate` renames the linked lyric project and relabels both the file's and the project's queue items from the queue's own copies (keeping their lyric flag); the dialog re-reads the stored record before saving so a link made meanwhile survives. The project player reloads when its song is renamed or gains/loses lyrics (without flashing the loading page); Now Playing's lyric action re-resolves on a new title or artist.
- Files:
  - New: `lib/features/player/domain/services/song_info_update.dart`, `lib/features/player/presentation/widgets/library_explorer_header.dart`.
  - Changed: `lib/core/widgets/app_vinyl_disc.dart`, `lib/features/player/data/services/just_audio_player_service.dart`, `lib/features/player/presentation/screens/{local_library_explorer_screen,player_screen,quick_play_screen}.dart`, `lib/features/player/presentation/widgets/{global_player_bar,local_media_metadata_dialog,now_playing_lyrics_project_action}.dart`.
  - Tests: `test/features/player/data/services/just_audio_player_service_test.dart`, `test/features/player/domain/services/song_info_update_test.dart`, `test/features/player/presentation/widgets/library_explorer_header_test.dart`, `test/core/widgets/app_vinyl_disc_test.dart`.
  - `docs/decisions.md` (D-059), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate.
- Notes:
  - The end of the queue is detected from just_audio's `ProcessingState.completed`; the session's completion handling is unchanged.
- Commit: `Stop the rhythm bars on pause, tidy the library toolbar, sync song info`
