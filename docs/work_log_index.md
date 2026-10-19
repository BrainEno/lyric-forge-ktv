# Work Log Index

> Navigation snapshot through 2026-10-19 21:22. Verify Git/current code before treating follow-up notes as unresolved.

## Read order

1. Read `AGENTS.md` and this index.
2. Read only the 1–3 relevant newest entries in `docs/work_log.md`.
3. Search `docs/work_log_archive.md` by topic/date only if needed; never load it whole by default.
4. Check `git status --short` and diffs before editing.

## Recent work areas

- **Lyrics ↔ local songs:** linking from transcription/import, self-healing resolver (item project ID → persisted `linkedProjectId` → same-audio-path fallback), auto-link on first lyric save, and queue `hasLyrics` enrichment. Key tests: `playback_lyrics_project_linker_test.dart`, `playback_lyrics_project_resolver_test.dart`, `file_project_repository_test.dart`, `local_media_metadata_playback_test.dart`, `now_playing_lyrics_project_action_test.dart`.
- **ASR downloads/proxy:** connect/no-data timeouts, retries and resumable `.part` downloads; setup progress separated from per-file progress; manual/environment/static Windows/macOS HTTP proxy resolution and independent proxy persistence. Key docs/tests: `docs/asr_runtime_installation.md`, `asr_download_http_client_factory_test.dart`, `asr_runtime_resume_contract_test.dart`, `retrying_asr_runtime_manager_test.dart`, `asr_install_experience_contract_test.dart`, `file_transcription_settings_store_test.dart`.
- **KTV microphone/recording:** monitoring, take recording/mix export, input device selection and persistence; physical device behavior was not fully verified in the log.
- **Player/LRC:** effective timestamp export, follow-play scrolling, editor return refresh, and KTV backing mode. Search archive for `LRC`, `auto-scroll`, `backing`, or `KTV`.

## Follow-up leads — re-check before acting

- Already-enqueued items may retain stale `hasLyrics` after a dead link is cleared.
- Creating lyrics in another project may silently replace an existing audio→project link; conflict confirmation was deferred.
- Real Windows/macOS microphone switching, latency, and end-to-end audio checks were not fully verified.
- Live Hugging Face proxy/download behavior was not tested end-to-end.
- The full analyzer was previously blocked by `WidgetTester.doubleTap` in `test/features/player/fullscreen_ktv_interaction_surface_test.dart`; verify whether this still applies.

## Archive map

- Apr 22–23, 2025: initial app, repositories, import, editor/player, quick play.
- Oct 9, 2026 11:46–12:03: timeline/LRC and player refresh.
- Oct 9, 2026 12:14–15:42: KTV microphone/recording and device support.
- Oct 19, 2026 15:17–16:11: ASR retry, progress, proxy and persistence.
- Oct 19, 2026 16:48–21:22: lyric association and playback queue.

## Maintenance

- Keep this index compact (target <80 lines, about 1,500 tokens); update only for changed focus, stable decisions, material risks, or navigation.
- Keep `docs/work_log.md` to 5–8 newest complete entries, preferably <120 lines.
- Move older complete entries verbatim to `docs/work_log_archive.md`; never delete history. Label uncertain follow-ups as leads and verify them.
