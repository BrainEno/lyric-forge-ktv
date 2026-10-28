# Handoff

## 目标
Continue hardening the local ASR lifecycle without dropping completed resumable work or weakening dual-engine quality behavior.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `341a8d7a244f388527066a0479ba107aac7a2d12`
- Active PR: [#213 — bound forced-alignment HTTP request lifetimes](https://github.com/BrainEno/lyric-forge-ktv/pull/213)
- Code-only head: `ed7111b01f7b47cb057d122d9093f37cef6ce607`
- The code-only head passed Flutter Quality Gate and all three ASR validation workflows. A documentation-refresh commit is being added; re-check Actions on the final PR head before merge.
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 本轮实现
- Apply one overall deadline to forced-alignment HTTP connect, request completion, and response-body reads.
- Abort the active request and close the HTTP client on timeout; force-closing the client aborts in-flight work and maps interruptions to `ForcedAlignmentException`.
- Track the active alignment client in the Qwen service so cancel/dispose aborts the alignment request before stopping the local server.
- Add loopback HTTP regression tests for a response body that stalls after headers and explicit force-close of a pending response.
- Repair the PR tree after discovering the formatter commit had accidentally replaced the full repository tree: the repaired PR now changes only the intended client, Qwen call-site, and corresponding test files.

## 下一步
1. Migrate resumable chunking's FFmpeg duration probe and chunk extraction to `AsrProcessSupervisor`, with bounded waits, cancellation escalation, bounded diagnostics, and cleanup of incomplete WAV files.
2. Preserve completed chunk JSON/manifest checkpoints across timeout or cancellation; add fault-injection coverage for these boundaries.
3. Bound high-quality shared audio preparation and remove only partial artifacts on failure.
4. Add real-child smoke checks for Windows and macOS; document direct-child versus process-tree guarantees rather than assuming identical behavior.

## 已知风险
- The code-only PR head has CI coverage, but the documentation-refresh head still needs checks before merge.
- Forced-alignment regression tests use a loopback HTTP server; full native Qwen/model integration has not been exercised here.
- Timeout budgets are heuristics and need real-song benchmarking on supported hardware.
- `AsrProcessSupervisor` guarantees bounded direct-child termination only; complete descendant cleanup remains unverified across supported OSes.

最后更新：2026-10-28 19:40（Asia/Taipei）
