# [2026-10-26 20:00] Disable MPV on-disk packet cache for audio playback

- Scope: Prevent the audio-only MPV backend from relying on an optional temporary disk-backed packet cache, while retaining normal in-memory and network buffering.
- Files: `packages/just_audio_media_kit/lib/mediakit_player.dart`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, and this entry.
- Validation:
  - Static source review confirms the MPV option is set in the adapter's readiness path before any media is opened.
  - MPV's manual defines `cache-on-disk` as storing packet data in a temporary file instead of memory; setting it to `no` leaves the normal cache available: https://mpv.io/manual/master/
  - The merged main baseline Quality Gate #275 passed formatting, work-log preflight, analyzer and tests: https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40311320773
  - Windows native playback cannot be run in this execution environment; warning removal and local/network playback still need smoke testing after rebuilding.
- Notes: This changes only `cache-on-disk` to `no`; it does not disable the normal cache or lower MPV log severity. The related upstream report notes that suppressing the warning alone did not necessarily fix first-play behavior: https://github.com/Pato05/just_audio_media_kit/issues/22. Treat this as a targeted prevention of the temporary disk-cache path, not proof that every playback symptom is resolved.
- Commit: `fix: disable MPV on-disk packet cache for audio-only playback`
