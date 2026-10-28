# Handoff

## 目标
Continue hardening the local ASR lifecycle without dropping completed resumable work or weakening dual-engine quality behavior.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `341a8d7a244f388527066a0479ba107aac7a2d12`
- Active PR: [#213 — bound forced-alignment HTTP request lifetimes](https://github.com/BrainEno/lyric-forge-ktv/pull/213)
- Code-only head: `ed7111b01f7b47cb057d122d9093f37cef6ce607`
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transcription/data/services/forced_alignment_http_client.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `test/features/transcription/forced_alignment_http_client_test.dart`
- `docs/engineering_risks_roadmap.md`
- `docs/log/entries/2026-10-28-1940-bound-forced-alignment-http-lifetimes.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/handoff.md`

## 本轮实现
- Apply one overall deadline to forced-alignment HTTP connect, request completion, and response-body reads.
- Abort the active request and close the HTTP client on timeout; force-closing the client aborts in-flight work and maps interruptions to `ForcedAlignmentException`.
- Track the active alignment client in the Qwen service so cancel/dispose aborts the alignment request before stopping the local server.
- Add loopback HTTP regression tests for a response body that stalls after headers and explicit force-close of a pending response.
- Repair the PR tree after discovering the formatter commit had accidentally replaced the full repository tree; the repaired code diff is limited to the intended client, Qwen call-site, and corresponding test.

## 检查结果
- Code-only head `ed7111b01f7b47cb057d122d9093f37cef6ce607` passed Flutter Quality Gate (run [40681387315](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387315)), ASR client checks (run [40681387092](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387092)), transcription settings validation (run [40681387199](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387199)), and transcription execution failure validation (run [40681387100](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387100)).
- The first documentation-refresh head `156c6764b66c3c0a45709adf5c61526181dffcec` failed only the work-log preflight: required handoff section headings were missing and the planned squash subject was not in branch history. This follow-up restores the headings and uses the exact intended PR subject; check Actions on the resulting head before merging.
- Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.

## 下一步
1. Confirm the documentation-refresh head passes all CI and merge PR #213.
2. Migrate resumable chunking's FFmpeg duration probe and chunk extraction to `AsrProcessSupervisor`, with bounded waits, cancellation escalation, bounded diagnostics, and cleanup of incomplete WAV files.
3. Preserve completed chunk JSON/manifest checkpoints across timeout or cancellation; add fault-injection coverage for these boundaries.
4. Bound high-quality shared audio preparation and run real-child smoke checks for Windows/macOS. Document direct-child versus process-tree guarantees rather than assuming identical behavior.

## 已知风险
- Forced-alignment regression tests use a loopback HTTP server; full native Qwen/model integration has not been exercised here.
- Timeout budgets are heuristics and need real-song benchmarking on supported hardware.
- `AsrProcessSupervisor` guarantees bounded direct-child termination only; complete descendant cleanup remains unverified across supported OSes.

最后更新：2026-10-28 19:43（Asia/Taipei）
