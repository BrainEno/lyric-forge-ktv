# Work Log Index

> Navigation snapshot through 2026-10-30. Verify Git/current code before treating follow-up notes as unresolved.

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

- **Recoverable JSON persistence (#221):** `AtomicJsonFile` keeps validated temp/backup sidecars and restores missing/invalid canonical stores. This branch uses direct POSIX rename for atomic replacement and retains Windows' recoverable delete/rename fallback; schemaVersion migration remains separate. Verify platform-specific behavior and all store consumers before closing the issue.

- **Cross-platform application identity:** Android namespace/application ID, iOS/macOS bundle identifiers, and Linux GTK application ID use `io.github.braineno.lyricforge`; Windows runner metadata uses the repository owner rather than `com.example`. `scripts/check_app_identifiers.sh` is enforced before Flutter setup in CI.

- **Media Hub upload reservation (#234):** Incoming uploads claim a final filename through an exclusive `.reserve` marker and write to a unique `.lyricforge-<uuid>.part` file. A concurrent same-name regression test validates distinct output names, both SHA-256 digests, and cleanup of temporary files.

- **Media Hub browser isolation (#227):** The native pinned-HTTPS service no longer sends wildcard CORS headers and rejects browser `OPTIONS` preflights. Native Media Hub clients do not require CORS; bearer auth and TLS pinning remain mandatory. See `http_media_hub_upload_test.dart` and the 2026-10-29 CORS hardening entry.

- **Media Hub bearer authentication (#222):** HTTP authorization requires a Bearer header; URL token parameters are stripped from remote-player proxy/rebase URLs and must not authorize requests. `mediaHubConstantTimeEquals` is shared by HTTP token validation and discovery proof checks; see `media_hub_discovery_auth_test.dart` and the #222 follow-up entry. Full timing guarantees remain bounded by Dart runtime behavior.

- **Flutter/Dart toolchain (#216):** `.fvmrc` is the active Flutter pin; the shared CI action and local shell/PowerShell quality/build scripts verify that Flutter and the `dart` executable on PATH use the same bundled SDK pair. See `docs/development-environment.md` and `scripts/check_flutter_sdk.*` before formatting changed Dart files.

- **Media Hub URL credentials (#222):** Remote artwork no longer gets a session token appended to URL query parameters. Artwork bytes are fetched through the pinned HTTPS client with Bearer Authorization; static regression contracts prevent restoring `Image.network` against a credential-bearing URI.

- **App startup/navigation:** route observer coalesces Navigator route changes and publishes the current route after the frame, avoiding a ValueNotifier notification during initial route restoration. Regression coverage: `current_route_observer_test.dart`.
- **Lyrics ↔ local songs:** linking from transcription/import, self-healing resolver (item project ID → persisted `linkedProjectId` → same-audio-path fallback), auto-link on first lyric save, queue `hasLyrics` enrichment, and an app-shell availability sync that retracts or raises that flag from the resolved project. Key tests: `playback_lyrics_project_linker_test.dart`, `playback_lyrics_project_resolver_test.dart`, `playback_lyrics_availability_test.dart`, `file_project_repository_test.dart`, `local_media_metadata_playback_test.dart`, `now_playing_lyrics_project_action_test.dart`.
- **ASR downloads/runtime:** the pinned Qwen Rust runtime's eager-attention Q/K/V transpose views must be made contiguous for CUDA matmul; both Windows CUDA and Intel Mac builds apply `tool/patches/qwen3-asr-eager-attention-contiguous.patch` and run the Rust regression. Fixed bundles ship as `asr-runtime-v2` with an explicit patch revision; the installer detects missing/stale runtime markers, stages/verifies a replacement before switching, preserves model weights, and invalidates the old Qwen readiness marker. Managed FFmpeg downloads are being hardened in the issue #217 PR with pinned release assets, pre-extraction SHA-256 checks and staged activation. Real Windows + RTX 5080 song self-check remains mandatory.
- **KTV microphone/recording:** monitoring, take recording/mix export, input device selection and persistence; physical device behavior was not fully verified in the log.
- **Player/LRC:** effective timestamp export, follow-play scrolling, editor return refresh, and KTV backing mode. Search entry files for `LRC`, `auto-scroll`, `backing`, or `KTV`.
- **GitHub Actions CI:** PR #147 adds an always-on Flutter quality gate for all PRs targeting `main`, `main` pushes, and manual dispatch. The issue #225 CI refactor centralizes the SDK version in `.fvmrc` through `.github/actions/setup-flutter/action.yml`, keeps the full suite in the universal quality gate, and leaves focused checks/native builds in specialist workflows. Work-log lint remains a preflight. Use `dart tool/work_log.dart new --timestamp "YYYY-MM-DD HH:mm" --slug <ascii-slug> --title <title>` for complete entry scaffolds, then `write` and `check`; required branch protection still needs to be enabled in repository Settings.
- **Lyric review / proofread v2:** PR #189 and #190 are merged. Review displays bounded ForcedAligner coverage diagnostics; `tool/forced_alignment_eval.dart` reports text recall/precision and boundary errors against manual references. Its `capture` subcommand records actual local `/v1/align` responses into a corpus, converts seconds to milliseconds, validates span/audio bounds, and refuses non-loopback endpoints. Use manually checked Chinese/English/Japanese samples on a rebuilt runtime before drawing accuracy conclusions or designing confirmed timestamp repair.
- **V2 line audition:** The proofread review dialog exposes original-versus-proposed time audition with each document's own global offset, and displays playback failures inline. Widget tests cover callback arguments and visible failure feedback; Windows/MPV seek and sound output still require end-to-end verification.
- **Highest-quality ASR fusion:** Secondary-only lyric lines are retained even when their timestamps overlap a long primary row, unless text fragments or near-identical segment timing indicate they are already represented. Both engine orders are covered by regression tests; real-song recall/WER still requires a manually checked corpus.
- **ASR transcript benchmarking:** `tool/asr_transcript_eval.dart` compares Whisper/Qwen/fusion output against manually checked references and enforces exact input/model/runtime provenance. `tool/asr_preprocessing_ab_eval.dart` compares per-engine normalization with the shared-WAV path, pairing each song/engine while requiring the same original source hash, reviewed reference, duration, model revision, and runtime version; it reports CER/token/edit-operation deltas and whether actual normalized WAV bytes changed. `tool/forced_alignment_eval.dart` separately measures span recall and timestamp boundary error. No metric substitutes for a checked real-song corpus.

## Follow-up leads — re-check before acting

- **Open-source product-quality roadmap:** [engineering_risks_roadmap.md](engineering_risks_roadmap.md) prioritizes persistence recovery, ASR lifecycle, Media Hub upload limits, separation/MVP scope, installable app packages, and real-song/mix quality gates. Third-party provenance/notices are scoped to artifacts actually bundled; they are not a general development or monetization gate.

- **Media Hub security (#218):** [PR #239](https://github.com/BrainEno/lyric-forge-ktv/pull/239) merged on 2026-10-29 after the final-head Flutter Quality Gate, KTV recovery validation, and Windows Debug build all passed. Physical Android-to-desktop pairing and real audio playback still need a device-level smoke test; protocol-v1 saved connections must pair again.
- **Media Hub uploads (#224):** The guardrail branch adds a 2 GiB default file cap, 30-second idle timeout, 45-minute total deadline, a 256 MiB free-space reserve with periodic probes, and two process-wide / one-per-session concurrency limits. Oversize, timeout, contention, and storage failures return 413, 408, 429, and 507 respectively. Validate final-head CI before merge; the `.part` reservation race tracked by #234 remains separate.
- **Recoverable JSON persistence:** `lib/core/persistence/atomic_json_file.dart` keeps a validated previous generation before replacement and restores invalid/missing canonical stores from valid temp/backup sidecars. See the newest work-log entry and verify all migrated stores in CI.
- **macOS Media Hub Release entitlement:** [PR #208](https://github.com/BrainEno/lyric-forge-ktv/pull/208) adds and CI-validates client/server entitlements in source plists and signed Debug/Release artifacts. LAN/Tailscale device smoke tests remain a separate end-to-end check.
- **Engineering review risk register:** [engineering_risks_roadmap.md](engineering_risks_roadmap.md) tracks the remaining ASR process-timeout, JSON-store scale, audio-clock alignment, and Media Hub token/range risks.

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
