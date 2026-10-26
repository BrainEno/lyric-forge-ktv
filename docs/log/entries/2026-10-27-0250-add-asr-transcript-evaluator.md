# [2026-10-27 02:50] Add a paired transcript evaluator for ASR engines

- Scope: Add repeatable CER/token error/WER comparisons for Whisper, Qwen, and fused lyrics against one manually checked reference per audio clip; report weighted per-engine and per-language metrics without claiming accuracy from smoke tests.
- Files: `tool/asr_transcript_eval.dart`, `test/tool/asr_transcript_eval_test.dart`, `docs/high_quality_asr.md`, `docs/work_log.md`, `docs/work_log_index.md`, `docs/handoff.md`, this entry.
- Validation:
  - Added tests for paired engine comparison, CJK WER suppression, full-width normalization, empty transcripts, weighted aggregation, invalid corpus data, and safe report output.
  - Flutter Quality Gate, ASR client checks, and transcription settings/full-regression checks => pending for this PR head.
- Notes: CER and token error rates use the shared lyric tokenizer and ignore case, whitespace, and punctuation. WER is only reported when neither side contains CJK. Timing/span quality remains the responsibility of the existing ForcedAligner evaluator. No real-song improvement is claimed without a manually reviewed corpus.
- Commit: `feat: add paired ASR transcript quality evaluator`
