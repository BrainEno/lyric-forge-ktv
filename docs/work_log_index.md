# Work Log Index

> Navigation snapshot through 2026-10-26. Verify Git/current code before treating follow-up notes as unresolved.

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

- **App startup/navigation:** route observer coalesces Navigator route changes and publishes the current route after the frame, avoiding a ValueNotifier notification during initial route restoration. Regression coverage: `current_route_observer_test.dart`.
- **Lyrics ↔ local songs:** linking from transcription/import, self-healing resolver (item project ID → persisted `linkedProjectId` → same-audio-path fallback), auto-link on first lyric save, queue `hasLyrics` enrichment, and an app-shell availability sync that retracts or raises that flag from the resolved project. Key tests: `playback_lyrics_project_linker_test.dart`, `playback_lyrics_project_resolver_test.dart`, `playback_lyrics_availability_test.dart`, `file_project_repository_test.dart`, `local_media_metadata_playback_test.dart`, `now_playing_lyrics_project_action_test.dart`.
- **ASR downloads/runtime:** the pinned Qwen Rust runtime's eager-attention Q/K/V transpose views must be made contiguous for CUDA matmul; both Windows CUDA and Intel Mac builds apply `tool/patches/qwen3-asr-eager-attention-contiguous.patch` and run the Rust regression. Fixed bundles ship as `asr-runtime-v2` with an explicit patch revision; the installer detects missing/stale runtime markers, stages/verifies a replacement before switching, preserves model weights, and invalidates the old Qwen readiness marker. Real Windows + RTX 5080 song self-check remains mandatory.
- **KTV microphone/recording:** monitoring, take recording/mix export, input device selection and persistence; physical device behavior was not fully verified in the log.
- **Player/LRC:** effective timestamp export, follow-play scrolling, editor return refresh, and KTV backing mode. Search entry files for `LRC`, `auto-scroll`, `backing`, or `KTV`.
- **GitHub Actions CI:** PR #147 adds an always-on Flutter quality gate for all PRs targeting `main`, `main` pushes, and manual dispatch. Work-log lint now runs as a preflight before expensive analysis/tests to fail quickly. Use `dart tool/work_log.dart new --timestamp "YYYY-MM-DD HH:mm" --slug <ascii-slug> --title <title>` for complete entry scaffolds, then `write` and `check`; required branch protection still needs to be enabled in repository Settings.
- **Lyric review / proofread v2:** PR #189 and #190 are merged. Review displays bounded ForcedAligner coverage diagnostics; `tool/forced_alignment_eval.dart` reports text recall/precision and boundary errors against manual references. Its `capture` subcommand records actual local `/v1/align` responses into a corpus, converts seconds to milliseconds, validates span/audio bounds, and refuses non-loopback endpoints. Use manually checked Chinese/English/Japanese samples on a rebuilt runtime before drawing accuracy conclusions or designing confirmed timestamp repair.

## Follow-up leads — re-check before acting

- Creating lyrics in another project may silently replace an existing audio→project link; conflict confirmation was deferred.
- A project-repository read failure is still treated as "no project", so a transient error could clear a lyric link; harden the resolver before relying on it in bulk workflows.
- Real Windows/macOS microphone switching, latency, and end-to-end audio checks were not fully verified.
- Live Hugging Face proxy/download behavior was not tested end-to-end.
- The analyzer was reported clean (0 issues project-wide) and the full test suite passed (513 tests, 2 skipped as of the E5 entry); vendored `packages/just_audio_media_kit` is excluded via `analysis_options.yaml` on purpose.
- The work-log harness lint (`dart tool/work_log.dart check`) runs in the universal GitHub Actions Flutter quality gate and the local quality-gate scripts.

## Follow-up leads — media backend

- `media_kit`/MPV terminal messages are independent of the route observer. The audio-only `just_audio_media_kit` adapter avoids the unsupported OSC runtime write and now explicitly sets `cache-on-disk=no` before opening media, preserving normal memory/network caching. Verify `lavf: Failed to create file cache` and first-play behavior on Windows after rebuilding; do not suppress MPV errors globally.

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
