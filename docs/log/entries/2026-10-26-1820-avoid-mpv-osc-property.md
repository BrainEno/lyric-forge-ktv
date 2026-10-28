# [2026-10-26 18:20] Avoid unsupported OSC property in audio-only MPV adapter

- Scope: Stop the audio-only just_audio_media_kit adapter from asking media_kit to write the unsupported MPV OSC runtime option, without globally suppressing MPV errors or changing cache behavior.
- Files: `packages/just_audio_media_kit/lib/mediakit_player.dart`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, and this entry.
- Validation:
  - Flutter Quality Gate #272 on source head `e1c2cfdc`: changed-Dart formatting passed; work-log preflight passed (0 errors / 0 warnings); `flutter analyze lib test` passed; all 721 Flutter tests passed.
  - CI run: https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40306279221
  - Native Windows playback was not available in CI; verify the `osc` line is gone in a Windows `flutter run` after rebuilding.
- Notes: `PlayerConfiguration.osc` defaults to false in media_kit 1.2.6; that makes this audio-only adapter attempt to set `osc=no` as a runtime property. The adapter has no video surface or OSC UI, so leave that unsupported option unset. `lavf: Failed to create file cache` is a separate issue and is not hidden by this change; it still needs reproduction with the specific audio source and playback outcome.
- Commit: `fix: avoid unsupported OSC property in audio-only player`
