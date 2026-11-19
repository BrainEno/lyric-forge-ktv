# [2026-11-30 09:30] Show automatic pairings in settings

- Scope: The round 12 handoff suggested it: the 曲库目录 card in settings is where people point the library at their lyric files, so it now says how many songs got their lyrics that way (D-034) and takes them straight to those songs. `LibraryLyricsAutoLinker.autoPairedCount` counts the songs in the library whose metadata carries a live `lyricAutoLink` record, the same songs the library's 自动配对 view lists. The card shows 已自动配对 N 首歌 with 在音乐库查看 (or 还没有按文件名自动配对的歌曲 when there are none), counts again after 更改… and 立即配对歌词, and again when the user comes back from the library, so songs unpaired there drop out of the number. A failed count leaves the line out instead of showing a wrong number. The jump is a new route, `/library/auto-paired`, which opens the songs section on the 自动配对 view. Every library route now resolves through `LocalMusicLibraryShell.targetFor`, which returns the section and the smart view, so the router lost its five near-identical cases and the mapping can be tested without the app services.
- Files:
  - `lib/features/player/domain/services/library_lyrics_auto_linker.dart` (`autoPairedCount`).
  - `lib/core/navigation/routes.dart` (`libraryAutoPaired`), `lib/app/app_router.dart`, `lib/features/player/presentation/screens/local_music_library_shell.dart` (`targetFor`, `LibraryShellTarget`, `initialSmartView`), `lib/features/player/presentation/screens/local_library_explorer_screen.dart` (`initialSmartView`).
  - `lib/features/settings/presentation/widgets/library_folder_settings_card.dart`, `lib/features/settings/presentation/settings_screen_dependencies.dart`, `lib/features/settings/presentation/screens/settings_screen.dart`, `lib/app/transcription_assembly.dart`.
  - Tests: `test/features/player/domain/services/library_lyrics_auto_linker_test.dart`, `test/features/settings/presentation/widgets/library_folder_settings_card_test.dart`, `test/features/player/presentation/screens/local_music_library_shell_test.dart`, `test/core/navigation/app_destinations_test.dart`.
- Validation:
  - Line lengths checked locally by code points; the settings feature reaches the library only through `core/navigation/routes.dart`, so the feature dependency graph is unchanged.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - `/library/auto-paired` starts with `/library/`, so the navigation rail highlights 音乐库, and pressing 音乐库 there opens the plain library.
  - Songs paired before round 12 have no record and are not counted, as in the library.
  - Not tried in a running app.
- Commit: `Show automatic pairings in settings`
