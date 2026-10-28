# [2026-10-25 17:05] Attach forced-alignment evidence to proofreading proposals

- Scope: Extend the ASR-first proofreading pipeline to accept validated word/span timing evidence, attach it to matching review rows as low-confidence forced-aligner tokens, and flag unmatched lines without changing lyric text or line timestamps.
- Files: lib/features/lyrics/domain/proofreading/proofread_result.dart, lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart, test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, this entry.
- Validation: Added tests for multilingual/punctuation-tolerant contiguous text matching, immutable source and proposed lyric timing, incomplete evidence review flags, ordering and audio-duration rejection. Remote CI must run format, analyze, full Flutter tests, and work-log lint; this environment has no local Dart/Flutter SDK.
- Notes: This consumes typed evidence only; it does not call the current ASR sidecar or claim that /v1/align exists. Matched tokens receive conservative confidence 60 and remain review evidence, not an automatic timing edit.
- Commit: `feat: attach forced-alignment evidence to review proposals`
