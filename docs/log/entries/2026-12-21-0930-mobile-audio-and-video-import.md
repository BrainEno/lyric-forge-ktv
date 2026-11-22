# [2026-12-21 09:30] Mobile audio and video import

- Scope: round 35, mobile import (D-056):
  - `MediaImportService` / `LocalMediaImportService`: pick audio or video from the system Files picker, or videos from the photo library; songs are copied into Documents/`Imported Audio` (a library root, visible in the iOS Files app), deduplicated by name and size, renamed "name (2)" on clashes. Videos are not kept: `MediaAudioExtractor` writes their sound track to an `.m4a` next to the songs, and failed outputs are deleted.
  - Native extractor on channel `io.github.braineno.lyricforge/media_audio`: iOS `AVAssetExportSession` with the AppleM4A preset, Android `MediaExtractor` + `MediaMuxer` copying an AAC track without re-encoding.
  - `runMediaImport`: source sheet, progress dialog, summary snack bar with 查看原因. Entry points on the home header, the empty home hero, the library's add button/menu and empty state; iOS no longer offers 添加音乐文件夹.
  - iPhone safe areas (D-057), from the user's screenshot: the library section strip pads for the status bar and its section pages drop the top inset (no double app bar inset); the phone chrome strips the bottom inset from the page and mini player when something sits below them, so only the tab bar pads for the home indicator.
- Files:
  - New: `lib/features/player/domain/services/{media_import_service,media_audio_extractor}.dart`, `lib/features/player/data/services/{local_media_import_service,method_channel_media_audio_extractor}.dart`, `lib/features/player/presentation/widgets/media_import_action.dart`, `android/app/src/main/kotlin/io/github/braineno/lyricforge/MediaAudioExtractor.kt`.
  - Changed: `lib/app/{app_services,local_library_assembly}.dart`, `lib/features/player/presentation/{local_library_dependencies,screens/listen_home_screen,screens/local_library_explorer_screen}.dart`, `ios/Runner/{AppDelegate.swift,Info.plist}`, `android/app/src/main/kotlin/io/github/braineno/lyricforge/MainActivity.kt`, `lib/app/app_chrome.dart`, `lib/features/player/presentation/screens/local_music_library_shell.dart`.
  - Tests: `test/features/player/data/services/{local_media_import_service,method_channel_media_audio_extractor}_test.dart`, `test/features/player/presentation/widgets/media_import_action_test.dart`, `test/features/player/presentation/screens/{listen_home_screen,local_music_library_shell}_test.dart`, `test/app/app_chrome_test.dart`.
  - `docs/decisions.md` (D-056, D-057), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow; Swift compiled by the iOS IPA workflow.
- Notes:
  - Android copies AAC tracks only; videos with other audio codecs are reported as unsupported rather than re-encoded.
- Commit: `Add mobile audio and video import`
