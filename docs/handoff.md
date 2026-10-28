# Handoff

## 目标
Continue hardening the local ASR lifecycle while keeping cancellation typed, partial artifacts clean, and completed chunk checkpoints resumable.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `981db7324b1a975ac827e170fb8dc5418151ca3f`
- Active PR: [#214 — supervise resumable audio chunk processes](https://github.com/BrainEno/lyric-forge-ktv/pull/214)
- Branch: `fix/supervise-resumable-chunk-processes-20261028`
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transcription/data/services/resumable_chunked_transcription_service.dart`
- `test/resumable_chunked_transcription_service_test.dart`
- `test/features/transcription/transcription_execution_failure_kind_test.dart`
- `docs/engineering_risks_roadmap.md`
- `docs/log/entries/2026-10-28-1945-supervise-resumable-chunk-processes.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/handoff.md`

## 本轮实现
- Replace the unbounded FFmpeg duration probe with a supervised process and a 45-second deadline; use `-t 0` to avoid decoding the full source merely to obtain its duration.
- Route chunk extraction through `AsrProcessSupervisor` with a source-size-aware 5–60-minute budget, bounded output tails, and bounded termination escalation.
- Map cancelled operations to the existing typed cancelled failure; classify timeouts/process-launch problems as environment failures and invalid media/extraction output as input failures.
- Remove incomplete chunk WAVs on timeout/cancellation/failure, without deleting completed chunk JSON checkpoints or discarding the manifest's completed IDs.
- Add fake-process regression tests for probe timeout, cancellation escalation, and checkpoint preservation after an unsuccessful chunk extraction.

## 检查结果
- Code/test head `4abb4411f443072c38753b765c4fd14a5f451227` passed all four PR workflows: Flutter Quality Gate (780 tests, work-log lint 0 errors/0 warnings), ASR client checks, transcription settings validation, and transcription execution failure validation. The documentation-refresh commit triggers new checks; verify the latest PR head before merging.
- Local Dart/Flutter commands were not run because SDKs are unavailable in this environment.
- Existing platform/process-tree limitation remains: the supervisor bounds direct-child termination, but descendant cleanup is not claimed across all supported OSes.

## 下一步
1. Review PR #214 final-head formatting, analyzer, focused test and full Flutter Quality Gate.
2. Apply equivalent lifecycle bounds to high-quality shared audio preparation and verify partial-output cleanup.
3. Add real-child smoke tests on Windows and macOS for direct-child/process-tree behavior.

## 已知风险
- Timeout budgets are heuristics and need real-song benchmarking on supported hardware.
- `-t 0` duration probing should be verified against the FFmpeg builds supported by Windows/macOS package paths; local SDK/runtime testing is unavailable here.
- `AsrProcessSupervisor` guarantees bounded direct-child termination only; descendant cleanup remains platform-dependent and unverified.

最后更新：2026-10-28 19:45（Asia/Taipei）
