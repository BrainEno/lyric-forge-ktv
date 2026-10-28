# Handoff

## 目标
Harden local ASR process lifetimes so stalled or cancelled jobs release the transcription queue predictably, without discarding completed resumable work or weakening dual-engine quality behavior.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `c9ebf6041264ff990db2d8fc7443158629c78ffc`
- Branch: `fix/qwen-process-lifetimes-20261028`
- PR: [#212 — bound Qwen transcription request and child process lifetimes](https://github.com/BrainEno/lyric-forge-ktv/pull/212)
- Code-only head validated before this documentation refresh: `f992af3050cb34a0ecbefca9292706b7b7c09218`
- Scope: Qwen executable probes, FFmpeg preprocessing, `/v1/transcribe` HTTP body wait, model-server startup/shutdown, and cancellation semantics; no UI changes.
- Local Dart/Flutter SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transcription/data/services/asr_process_supervisor.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `test/features/transcription/qwen3_asr_native_transcription_service_test.dart`
- `docs/engineering_risks_roadmap.md`
- `docs/log/entries/2026-10-28-1818-bound-qwen-transcription-lifetimes.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/handoff.md`

## 本轮实现
- Route Qwen executable probes and FFmpeg preprocessing through `AsrProcessSupervisor`, with a 10-second executable-probe budget and source-size-aware 5–60-minute FFmpeg budget.
- Bound the full Qwen `/v1/transcribe` response-body wait to a normalized-WAV-duration budget (5–120 minutes), while preserving the active request for cancellation until the body has completed.
- Use a two-minute elapsed-time deadline for model-server startup and bounded termination escalation for cancellation, disposal, and server shutdown.
- Map forced-alignment cancellation back to a typed cancelled result; remove incomplete Qwen FFmpeg output on failure.
- Add fake-process regression coverage for cancellation escalation, cancelled failure classification, partial-WAV cleanup, and Qwen timeout-budget scaling.

## 检查结果
- Flutter Quality Gate passed on the code-only head: `01:21 +775: All tests passed!` (run [40670616029](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40670616029)).
- ASR client checks passed (run [40670616102](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40670616102)).
- Transcription settings validation passed (run [40670615909](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40670615909)).
- Transcription execution failure validation passed (run [40670615863](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40670615863)).
- This documentation refresh creates a new PR head; check the latest PR Actions before merge.
- Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.

## 下一步
1. Add a request deadline and reliable abort/cancellation behavior to `ForcedAlignmentHttpClient` `/v1/align`, with a regression test for a stalled response.
2. Supervise resumable chunking's FFprobe duration probing and FFmpeg chunk extraction while preserving completed checkpoints.
3. Bound high-quality shared audio preparation and test partial-artifact cleanup.
4. Run real-child process smoke tests on Windows and macOS, including validation of direct-child and process-tree termination behavior.

## 已知风险
- Timeout budgets are heuristics and need real-song benchmarking on supported hardware.
- `/v1/align` is separate from the newly bounded `/v1/transcribe` request and remains without its own explicit deadline.
- Resumable FFprobe/FFmpeg and high-quality shared normalization have not yet migrated to the shared supervisor.
- The supervisor provides bounded direct-child termination; complete descendant/process-tree cleanup is not claimed across every supported OS.

最后更新：2026-10-28 18:18（Asia/Taipei）
