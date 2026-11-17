# [2026-11-21 12:00] Fix Qwen chunk loops and detect block loops

- Scope: Fix the user-reported bug where a Qwen3-ASR draft of "Riders on the Storm" repeats the same two lines from about 1:30 to the end, over instrumental and sung parts alike (D-024).
  - Root cause.
    - With timestamps on, `qwen3-asr-rs` cuts audio into chunks of at most 180 s and decodes each one greedily, with no repetition penalty. Its built-in repetition fix only handles patterns of up to 20 characters repeated 20 times.
    - The per-chunk budget assumed a single 1200 s chunk and gave a four-minute song 2176 tokens per chunk. A decoder cycling through a couplet filled that budget, and the forced aligner spread the repeated text over the whole chunk.
    - The "Song title / Artist / Album" context was copied into instrumental chunks.
  - Qwen requests (`qwen3_asr_native_transcription_service.dart`).
    - Every request sends `chunk_max_sec = 30` and a one-chunk budget of `max(256, 128 + min(sec, chunk) × 8)`: 368 tokens.
    - The context is only the project's recognition terms (`qwen_recognition_context.dart`); the project workflow and the independent rerun no longer build a title/artist context.
    - When an old runtime fails with "tokenized word_list is empty" (a chunk decoded to punctuation only), the request is retried once with 180 s chunks.
    - The metadata records `qwenChunkSeconds`, `qwenChunkFallback` and `qwenContextTerms`.
  - Runtime: new `tool/patches/qwen3-asr-skip-unalignable-chunks.patch`, applied by both platform jobs of `build-asr-runtime.yml`.
    - It skips chunks without a letter or digit before alignment, as upstream already does for empty chunks.
    - It is listed under `behaviorPatches` in the bundle manifest, not in the compatibility revision, so existing installs stay valid.
  - Loop check: `LyricAsrLoopKind.repeatedBlock`.
    - It finds a group of 2–4 rows repeated back to back at least three times (strong from four), and keeps two passes.
    - The dialog note reads "N 行一组连续循环 M 遍，删除 K 行", and draft health counts the rows.
- Experiment: CPU runtime at the pinned revision on GitHub Actions, run 44011875090. It used CC-licensed songs from JamendoLyrics with line-level reference timing (Ridgway, The Rinn, The madpix project, Avercage, Songwriterz, Kinematic), each about four minutes, plus vocal-gated copies of three of them.

  | model | config | max_new_tokens | runs | mean WER | words outside sung lines | lines / reference |
  |---|---|---|---|---|---|---|
  | 0.6B | 30 s chunks, title/artist context | 368 | 9 | 0.469 | 105 | 283/334 |
  | 0.6B | 30 s chunks, no context | 368 | 8 | 0.455 | 55 | 245/284 |
  | 0.6B | 60 s chunks, title/artist context | 608 | 9 | 0.522 | 29 | 215/334 |
  | 1.7B | 60 s chunks, title/artist context | 608 | 9 | 0.394 | 54 | 310/334 |

  - The 30 s run with context reproduced a loop at 95 s in Avercage ("Just keep burning… Hot, hot, hot…", 939 characters). The new budget keeps it inside one chunk.
  - Instrumental chunks with context came back as "Embers. Artist: Avercage."
  - One 30 s run without context hit the "word_list is empty" failure on a 0.54 s tail; this is what the patch and the retry cover.
  - The old-budget configurations ran more than an hour per model on CPU without finishing (see Notes).
- Files:
  - New: `lib/features/transcription/domain/models/qwen_recognition_context.dart`, `tool/patches/qwen3-asr-skip-unalignable-chunks.patch`.
  - Changed: `qwen_decode_budget.dart`, `qwen3_asr_native_transcription_service.dart`, `local_project_transcription_workflow.dart`, `independent_project_rerun_service.dart`, `transcription_models.dart` (doc), `lyric_asr_loop_detector.dart`, `lyric_asr_loop_dialog.dart`, `lyric_draft_health_service.dart` (doc), `build-asr-runtime.yml`.
  - Tests: `qwen_decode_budget_test.dart` (rewritten), `qwen_recognition_request_test.dart`, `lyric_asr_block_loop_test.dart`, and a couplet case in `lyric_loop_and_word_timing_widgets_test.dart`.
  - Docs: `decisions.md` (D-024), `high_quality_asr.md` (chunking corrected: timestamped requests use at most 180 s chunks, not 1200 s), `asr_runtime_installation.md`, handoff.
- Validation: VALIDATION_PENDING
- Notes: Word error rates are high for every setup on these mixes; the comparison is relative. The 30 s chunk length and the block thresholds are empirical.
- Commit: `Fix Qwen chunk loops and detect block loops`
