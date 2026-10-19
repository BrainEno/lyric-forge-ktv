# Work Log Index

> Navigation snapshot through 2026-10-19 22:09. Verify Git/current code before treating follow-up notes as unresolved.

## Read order

1. Read `AGENTS.md` and this index.
2. Read only the 1–3 relevant entry files in `docs/log/entries/` (`Get-ChildItem docs/log/entries | Sort-Object Name`).
3. Search `docs/log/entries/` or `docs/work_log_archive.md` by topic/date only when older history matters; never load the whole directory.
4. Resuming an interrupted session? Read `docs/handoff.md` first, then this index.
5. Check `git status --short` and diffs before editing.

## Log layout

- `docs/log/entries/<yyyy-mm-dd-hhmm>-<slug>.md` — one immutable file per completed task; bodies live here, never moved or deleted.
- `docs/work_log.md` — **generated** active summary (newest 8 entries). Regenerate with `dart tool/work_log.dart write`; verify with `dart tool/work_log.dart check`. Do not hand-edit.
- `docs/work_log_archive.md` — stage-grouped navigation for older entries.
- `docs/decisions.md` — durable decisions that still bind future work.
- `docs/handoff.md` — single-slot interruption handoff; overwrite before ending a session.

## Recent work areas

- **Lyrics ↔ local songs:** linking from transcription/import, self-healing resolver (item project ID → persisted `linkedProjectId` → same-audio-path fallback), auto-link on first lyric save, and queue `hasLyrics` enrichment. Key tests: `playback_lyrics_project_linker_test.dart`, `playback_lyrics_project_resolver_test.dart`, `file_project_repository_test.dart`, `local_media_metadata_playback_test.dart`, `now_playing_lyrics_project_action_test.dart`.
- **ASR downloads/proxy:** connect/no-data timeouts, retries and resumable `.part` downloads; setup progress separated from per-file progress; manual/environment/static Windows/macOS HTTP proxy resolution and independent proxy persistence. Key docs/tests: `docs/asr_runtime_installation.md`, `asr_download_http_client_factory_test.dart`, `asr_runtime_resume_contract_test.dart`, `retrying_asr_runtime_manager_test.dart`, `asr_install_experience_contract_test.dart`, `file_transcription_settings_store_test.dart`.
- **KTV microphone/recording:** monitoring, take recording/mix export, input device selection and persistence; physical device behavior was not fully verified in the log.
- **Player/LRC:** effective timestamp export, follow-play scrolling, editor return refresh, and KTV backing mode. Search entry files for `LRC`, `auto-scroll`, `backing`, or `KTV`.

## Follow-up leads — re-check before acting

- Already-enqueued items may retain stale `hasLyrics` after a dead link is cleared.
- Creating lyrics in another project may silently replace an existing audio→project link; conflict confirmation was deferred.
- Real Windows/macOS microphone switching, latency, and end-to-end audio checks were not fully verified.
- Live Hugging Face proxy/download behavior was not tested end-to-end.
- The analyzer and the full test suite are green (0 error, 0 warning, 310 tests passing) and `scripts/quality_gate.ps1` passes end to end.
- 149 style infos remain in `lib`/`test` (116× `prefer_interpolation_to_compose_strings`, 15× `unnecessary_underscores`, 5× `use_null_aware_elements`, and a few one-offs). They are non-fatal in CI and in the local gate; clearing them is a separate cleanup slice.
- The work-log harness ships a lint (`dart tool/work_log.dart check`) that both quality gates run; it is not yet wired into a GitHub workflow.

## Archive map

- Apr 22–23, 2025: initial app, repositories, import, editor/player, quick play.
- Oct 9, 2026 11:46–12:03: timeline/LRC and player refresh.
- Oct 9, 2026 12:14–15:42: KTV microphone/recording and device support.
- Oct 19, 2026 15:17–16:11: ASR retry, progress, proxy and persistence.
- Oct 19, 2026 16:48–21:22: lyric association and playback queue.

## Maintenance

- Keep this index compact (target <80 lines); update only for changed focus, stable decisions, material risks, or navigation.
- New task → write one entry file, run `dart tool/work_log.dart write`, add the aged-out line to the archive stage section, update this index only if focus/decisions/risks changed.
- Never delete entry files; superseded decisions are marked `已取代` in `docs/decisions.md`.
