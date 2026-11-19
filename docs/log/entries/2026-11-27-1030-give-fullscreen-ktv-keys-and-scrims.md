# [2026-11-27 10:30] Give fullscreen KTV keys and scrims

- Scope: Audit leftover "immersive KTV controls". In fullscreen KTV every key only revealed the controls: Space did nothing (the app-wide shortcut lets Space through only when nothing is focused, and the surface keeps focus) and seeking needed Shift. `FullscreenKtvInteractionSurface` now takes the keys a video player would and hands them to a new `onCommand`: Space play/pause (only while the surface itself has focus, so a button reached with Tab still activates), bare or Shift ←/→ seek by `GlobalPlaybackShortcuts.seekStep` with key repeat, Ctrl/⌘+←/→ previous/next; a handled command shows the controls, an unhandled one bubbles. The screen runs the commands through `GlobalPlaybackShortcuts.run`. Clicking the lyrics takes focus back from a tabbed button. The control layer gets a bold title with the artist under it, black-to-clear gradient scrims behind the top and bottom groups (pointer-transparent, so nothing below is blocked), "退出全屏 KTV（Esc）" and a key hint line on desktop. A failed lyric load shows `AppErrorState` with a retry instead of a raw red `Text`.
- Files:
  - `lib/features/player/presentation/widgets/fullscreen_ktv_interaction_surface.dart`.
  - `lib/features/player/presentation/screens/immersive_ktv_screen.dart`.
  - `test/features/player/fullscreen_ktv_keyboard_test.dart` (new: Space, bare/Shift/Ctrl/Meta arrows, repeat, Alt and unknown keys, refused commands bubble, reveal, Tab-focused button keeps Space, key hints per platform).
  - `test/features/player/presentation/screens/immersive_ktv_recording_test.dart` (title and artist, scrims, key hint on desktop only, keys reach the session, keys reveal hidden controls, no-op without a song, error state with retry).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Retry reloads the lyrics of the playing song when there is one, else the project the screen opened with.
- Commit: `Give fullscreen KTV keys and scrims`
