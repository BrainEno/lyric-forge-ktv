# [2026-10-26 18:00] Defer route observer notifications until after build

- Scope: Prevent the startup assertion caused by Navigator restoring its initial route while the app-shell ValueListenableBuilder is being built; coalesce route changes and publish the latest name after the current frame.
- Files: `lib/main.dart`, `lib/core/navigation/current_route_observer.dart`, `test/core/navigation/current_route_observer_test.dart`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, and this entry.
- Validation:
  - Flutter Quality Gate #267 on source head `79de9fba`: changed-Dart formatting passed; work-log lint passed with 0 errors and 0 warnings; `flutter analyze lib test` passed; all 721 Flutter tests passed.
  - Root widget workflow #6 on source head `79de9fba`: `flutter analyze lib/main.dart test/widget_test.dart`, `flutter test test/widget_test.dart`, the named mobile-root regression, and the full `flutter test` suite passed.
  - Latest run: https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40303806179
  - Root widget run: https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40303806271
- Notes: The `media_kit` `osc` property message is emitted by the media-kit/MPV integration; application code does not set `osc`. The `lavf: Failed to create file cache` message is a separate MPV/FFmpeg source/cache diagnostic. A related `just_audio_media_kit` report exists at https://github.com/Pato05/just_audio_media_kit/issues/22, but this log alone does not prove the same cause or that playback failed. Do not suppress global media logs; reproduce against the exact audio source before changing cache behavior.
- Commit: `fix: avoid notifier updates during Navigator restoration`
