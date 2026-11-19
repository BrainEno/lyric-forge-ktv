# [2026-11-28 13:00] Pair lyric files in the library folder

- Scope: User request (导出的歌词文件放在默认曲库目录能被自动识别，曲库目录可设置), decision D-033. New 曲库目录 setting: `LibraryFolderSettings` resolves the custom folder, then the first library folder, then the system 音乐 folder (`systemMusicFolder`); choosing a folder also adds it to the library, resetting only forgets the choice. `LibraryLyricsAutoLinker` finds LRC/ASS/VTT/SRT files in the library folder (recursively) and beside each song without lyrics, pairs them with `LibraryLyricFileMatcher` (beside song → same file name → artist and title → title; ties are skipped), imports each file into the song's project exactly like 导入歌词 (shared `projectWithImportedLyrics`, `lyricSource: library-folder`, `lyricImport.automatic`) and links it. Songs already linked or with a lyric project are never touched; an empty project for the song is filled. The library pairs on open and on rescan and says which songs got lyrics; settings gets a 音乐库 group with the 曲库目录 card (change, reset, 立即配对歌词). The lyric export dialog now opens in the library folder.
- Files:
  - `lib/features/player/domain/services/library_folder_settings.dart`, `library_lyric_file_matcher.dart`, `library_lyrics_auto_linker.dart`, `imported_lyrics_project.dart` (new).
  - `lib/features/player/data/services/file_library_folder_store.dart` (new: store and `listLyricFiles`).
  - `lib/features/player/presentation/widgets/library_lyrics_link_text.dart` (new), `local_song_lyrics_import_action.dart` (uses the shared builder), `local_library_dependencies.dart`, `screens/local_library_explorer_screen.dart`.
  - `lib/features/settings/presentation/widgets/library_folder_settings_card.dart` (new), `settings_screen_dependencies.dart`, `screens/settings_screen.dart`.
  - `lib/features/lyrics/data/services/local_lyric_file_export_service.dart` (`initialDirectory`).
  - `lib/app/app_services.dart`, `local_library_assembly.dart`, `transcription_assembly.dart`.
  - Tests: `test/features/player/domain/services/library_lyric_file_matcher_test.dart`, `library_folder_settings_test.dart`, `library_lyrics_auto_linker_test.dart`, `imported_lyrics_project_test.dart`, `test/features/player/data/services/file_library_folder_store_test.dart`, `test/features/player/presentation/widgets/library_lyrics_link_text_test.dart`, `test/features/settings/presentation/widgets/library_folder_settings_card_test.dart`.
  - `docs/decisions.md` (D-033).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; format, analyze and tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Plain `.txt` files are not paired automatically: music folders hold many text files that are not lyrics. They can still be imported by hand.
  - The settings card lives in the settings feature and only imports the player domain; the result sentence is built in the assembly layer, so no new cross-feature presentation import.
  - Not tried in a running app; the system 音乐 folder on Android needs storage permission, otherwise the folder lists nothing and pairing is silently skipped.
- Commit: `Pair lyric files in the library folder`
