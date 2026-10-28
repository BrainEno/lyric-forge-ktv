# [2026-10-28 19:40] Bound forced-alignment HTTP request lifetimes

- Scope: Prevent a stalled forced-alignment request or response body from holding a lyric review/transcription workflow indefinitely; make timeout, force-close, and Qwen cancellation abort pending HTTP work.
- Files: `lib/features/transcription/data/services/forced_alignment_http_client.dart`, `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`, `test/features/transcription/forced_alignment_http_client_test.dart`, `docs/engineering_risks_roadmap.md`, `docs/log/entries/2026-10-28-1940-bound-forced-alignment-http-lifetimes.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.
- Validation:
  - Code/test head `ed7111b01f7b47cb057d122d9093f37cef6ce607` passed Flutter Quality Gate (run [40681387315](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387315)).
  - ASR client checks passed (run [40681387092](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387092)).
  - Transcription settings validation passed (run [40681387199](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387199)).
  - Transcription execution failure validation passed (run [40681387100](https://github.com/BrainEno/lyric-forge-ktv/actions/runs/40681387100)).
  - Local Dart/Flutter commands were not run because SDKs are unavailable in this environment. The documentation-refresh commit must be checked separately.
- Notes: The timeout is one elapsed-time deadline across connect/request/body rather than a fresh budget per await. The client aborts active requests on timeout/forced close; the Qwen service aborts forced alignment before stopping its native server. Regression tests use loopback HTTP, not a real model server. The PR branch tree was repaired after a formatting commit accidentally omitted unrelated repository files; the final diff against main is limited to the three intended source/test files.
- Commit: `fix: bound forced-alignment HTTP request lifetimes (#213)`
