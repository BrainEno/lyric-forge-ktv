# Handoff

## 目标
Harden local ASR subprocess lifecycle so stalled or cancelled jobs cannot hold the transcription queue indefinitely, while preserving resumable artifacts and existing dual-engine quality behavior.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: 7e3a929ae3af279bb9182246db51a82d3964836a
- Branch: fix/whisper-cli-process-timeouts-20261028
- PR: [#211 — bound Whisper CLI process lifetimes](https://github.com/BrainEno/lyric-forge-ktv/pull/211).
- Scope: shared process supervisor + Whisper CLI timeout/cancellation integration; no UI changes.
- Local Dart/Flutter SDKs are unavailable in this environment; GitHub Actions is the validation gate.

## 已改文件
- lib/features/transcription/data/services/asr_process_supervisor.dart
- lib/features/transcription/data/services/whisper_cpp_transcription_service.dart
- test/features/transcription/asr_process_supervisor_test.dart
- docs/engineering_risks_roadmap.md
- docs/log/entries/2026-10-28-1745-bound-whisper-cli-process-lifetimes.md
- docs/work_log.md
- docs/work_log_archive.md
- docs/handoff.md

## 本轮实现
- Introduced bounded subprocess execution, bounded stdout/stderr tails and stream draining, timeout diagnostics, graceful termination, and force-kill escalation.
- Added operation-specific budgets: 10-second executable probe, source-size-aware 5–60-minute FFmpeg normalization, and normalized-WAV-duration-aware 5–120-minute whisper.cpp inference.
- Routed Whisper cancellation through the same bounded termination escalation rather than issuing a single kill signal.
- Deletes partial normalized WAV and Whisper JSON outputs on failure/timeout.
- Explicitly leaves Qwen server/request, resumable FFprobe/FFmpeg, and high-quality shared normalization for a separate follow-up phase.

## 检查结果
- Flutter Quality Gate passed: `01:13 +773: All tests passed!`; work-log lint 0 errors / 0 warnings.
- ASR client checks passed.
- Transcription settings validation passed.
- Transcription execution failure validation passed.
- The above results were on the application-code head before this documentation update; the docs-only commit will trigger the quality gate again.
- Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.

## 下一步
1. Verify CI on the final PR head and correct any documentation-contract failures.
2. Apply the same supervised timeout/cancellation mechanism to Qwen FFmpeg/request/server shutdown, resumable duration probing/chunk extraction, and high-quality shared normalization.
3. Verify real-child timeout/cancellation behavior on Windows and macOS.

## 已知风险
- Current integration covers the whisper.cpp adapter; other process paths can still wait without operation-specific deadlines.
- The timeout budgets are heuristics and need real-song benchmarking on supported hardware.
- The supervisor terminates the direct child; complete descendant/process-tree cleanup is not claimed across all supported operating systems.

最后更新：2026-10-28 17:45（Asia/Taipei）
