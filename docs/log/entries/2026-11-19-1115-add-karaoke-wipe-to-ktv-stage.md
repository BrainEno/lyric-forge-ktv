# [2026-11-19 11:15] Add a karaoke wipe to the KTV stage

- Scope: UI/UX audit K-01. The full-screen KTV stage only switched whole lines; the line being sung never showed how far the singer was. The current line is now coloured unit by unit (a Han character, a kana, a Latin word with its punctuation) as it is sung: sung units turn accent green and the unit being sung blends from white to green.
- Files:
  - `lib/features/player/presentation/widgets/ktv_karaoke_line.dart` (new): `ktvSungUnits` reuses `LyricKaraokeTimingService` (the karaoke export's syllable split and duration estimate) and `LyricWordTimingService` (real word timing from the forced aligner or word-by-word tap-to-sync), so the stage highlights exactly what a word-timed LRC/ASS export would. `KtvKaraokeLine` renders the spans and, while playing, advances its own position estimate every frame from the last reported position (at most 400 ms ahead) so the colour moves smoothly between position updates.
  - `fullscreen_ktv_lyric_stage.dart` (current slot uses `KtvKaraokeLine`; new `isPlaying`; the file was still in the pre-3.7 format style and is now tall style), `immersive_ktv_screen.dart` (passes `playback.isPlaying`).
  - Test: `test/features/player/presentation/widgets/ktv_karaoke_line_test.dart` (new: even spread, Latin syllable weights, real word timing, global offset, rows without an end, span colours, frame-by-frame estimate and its cap, pause).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate. The existing stage test (`current:<ms>` key, white base style, `find.text`) keeps working because the karaoke line is a `Text.rich` with that key and base style. The immersive screen test's fake playback is idle, so no ticker runs there.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - A row with no usable end is closed at the next row's start; with neither it is shown as sung as soon as it starts.
  - The ticker only runs while playback is playing and stops on pause; it rebuilds one `Text` per frame.
  - Not checked on a device: the wipe's smoothness with real position updates, and readability of the green on bright artwork-less black.
- Commit: `Add a karaoke wipe to the KTV stage`
