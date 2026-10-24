# Work Log Index

> Navigation snapshot through 2026-10-24. Verify Git/current code before treating follow-up notes as unresolved.

## Read order

1. Read `AGENTS.md` and this index.
2. Read only the 1–3 relevant entry files in `docs/log/entries/` (`Get-ChildItem docs/log/entries | Sort-Object Name`).
3. Search `docs/log/entries/` or `docs/work_log_archive.md` by topic/date only when older history matters; never load the whole directory.
4. Resuming an interrupted session? Read `docs/handoff.md` first, then this index.
5. Check `git status --short` and diffs before editing.

## Log layout

- `docs/log/entries/<yyyy-mm-dd-hhmm>-<slug>.md` — one immutable file per completed task; bodies live here, never moved or deleted.
- `docs/work_log.md` — **generated** active summary (newest 8 entries). `dart tool/work_log.dart write` regenerates it, syncs the index snapshot date, and maintains archive links for aged-out entries; verify with `dart tool/work_log.dart check`. Do not hand-edit.
- `docs/work_log_archive.md` — stage-grouped navigation for older entries, plus an automatically maintained fallback section for references not yet grouped by stage.
- `docs/decisions.md` — durable decisions that still bind future work.
- `docs/handoff.md` — single-slot interruption handoff; overwrite before ending a session.

## Recent work areas

- **Lyrics ↔ local songs:** linking from transcription/import, self-healing resolver (item project ID → persisted `linkedProjectId` → same-audio-path fallback), auto-link on first lyric save, queue `hasLyrics` enrichment, and an app-shell availability sync that retracts or raises that flag from the resolved project. Key tests: `playback_lyrics_project_linker_test.dart`, `playback_lyrics_project_resolver_test.dart`, `playback_lyrics_availability_test.dart`, `file_project_repository_test.dart`, `local_media_metadata_playback_test.dart`, `now_playing_lyrics_project_action_test.dart`.
- **ASR downloads/proxy:** connect/no-data timeouts, retries and resumable `.part` downloads; manual/environment/static Windows/macOS HTTP proxy resolution; official ModelScope manifest/checksum fallback; preflight validates both ModelScope manifest and file endpoints; local HTTP behavior tests cover fallback, Range resume, checksum verification and cross-source mismatch rejection. Real multi-gigabyte model download and native dual-engine load remain manual acceptance items. Key docs/tests: `docs/asr_runtime_installation.md`, `managed_model_asr_runtime_manager_http_test.dart`, `asr_download_http_client_factory_test.dart`, `asr_runtime_resume_contract_test.dart`, `retrying_asr_runtime_manager_test.dart`, `asr_install_experience_contract_test.dart`.
- **KTV microphone/recording:** monitoring, take recording/mix export, input device selection and persistence; physical device behavior was not fully verified in the log.
- **Player/LRC:** effective timestamp export, follow-play scrolling, editor return refresh, and KTV backing mode. Search entry files for `LRC`, `auto-scroll`, `backing`, or `KTV`.
- **GitHub Actions CI:** PR #147 adds an always-on Flutter quality gate for all PRs targeting `main`, `main` pushes, and manual dispatch. The gate runs full analyzer/tests/work-log lint; required branch protection still needs to be enabled in repository Settings.
- **Lyric review / proofread v2:** PRs #141 and #143–#145 are in `main`; PR #164 adds T7 shared pipeline invariants and is now merged into `main`. PR #165 integrates the T8 strategy chooser, line-by-line proposal review, green-only batch apply, explicit amber acceptance, grey-row restore, line audition, and existing snapshot undo. Its code-only CI run passed all 649 tests; after documentation sync a final gate will rerun. ASR-first UI still lacks a second-transcript input, and real-device playback/responsive smoke checks remain manual.

## Follow-up leads — re-check before acting

- Creating lyrics in another project may silently replace an existing audio→project link; conflict confirmation was deferred.
- A project-repository read failure is still treated as "no project", so a transient error could clear a lyric link; harden the resolver before relying on it in bulk workflows.
- Real Windows/macOS microphone switching, latency, and end-to-end audio checks were not fully verified.
- Live Hugging Face proxy/download behavior was not tested end-to-end.
- The analyzer was reported clean (0 issues project-wide) and the full test suite passed (513 tests, 2 skipped as of the E5 entry); vendored `packages/just_audio_media_kit` is excluded via `analysis_options.yaml` on purpose.
- The work-log harness lint (`dart tool/work_log.dart check`) runs in the universal GitHub Actions Flutter quality gate and the local quality-gate scripts.

## Archive map

- Apr 22–23, 2025: initial app, repositories, import, editor/player, quick play.
- Oct 9, 2026 11:46–12:03: timeline/LRC and player refresh.
- Oct 9, 2026 12:14–15:42: KTV microphone/recording and device support.
- Oct 19, 2026 15:17–16:11: ASR retry, progress, proxy and persistence.
- Oct 19, 2026 16:48–21:22: lyric association and playback queue.

## Maintenance

- Keep this index compact (target <80 lines); update only for changed focus, stable decisions, material risks, or navigation.
- New task → write one entry file, run `dart tool/work_log.dart write` (it syncs summary, snapshot date, and missing archive references), then run `dart tool/work_log.dart check`. Update this index body only if focus/decisions/risks changed; optionally group auto-archived references by stage.
- Never delete entry files; superseded decisions are marked `已取代` in `docs/decisions.md`.
