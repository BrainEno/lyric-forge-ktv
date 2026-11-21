# Highest Quality Local ASR Mode

## Goal

Highest Quality mode is the accuracy-first desktop transcription path for
high-end NVIDIA systems.

The current target profile is:

- Windows desktop
- NVIDIA RTX-class GPU
- CUDA-capable native Qwen3-ASR runtime
- Qwen3-ASR 1.7B
- Qwen3 ForcedAligner 0.6B
- whisper.cpp large-v3 as an independent second opinion
- FFmpeg for deterministic audio preprocessing

This mode intentionally favors recognition quality over minimum runtime.

## Smoke-test boundary

The advanced real-audio smoke test verifies that the managed runtime can execute
the production flow and persist an editable lyric project. It does **not**
calculate lyric recall, word error rate, omitted-line rate, or timestamp
accuracy. A run can complete while still producing an incomplete transcript.
Treat the generated lyric document as a draft and compare it with a manually
checked reference before judging recognition quality.

## Pipeline

```text
project audio
  -> prefer vocal stem
  -> normalized/original fallback when no vocal stem exists
  -> FFmpeg 16 kHz mono PCM
  -> Whisper large-v3 full-song transcript (current Windows RTX 5080 default)
  -> Qwen3-ASR full-song second opinion
  -> time-overlap comparison in both directions
  -> conservative text alternatives + unmatched secondary-only lines
  -> editable LyricDocument
```

## Shared FFmpeg normalization contract

The Qwen and Whisper adapters both use
`AsrAudioNormalization.ffmpegArguments` for the same input format: 16 kHz,
mono, signed 16-bit PCM WAV. The executable, original input path and all
normalization options are now assembled by one shared helper; only the output
path differs per engine. Arguments are passed as a process argument vector, not
as a shell command, so paths containing spaces remain intact.

Highest Quality mode now creates one `high_quality_shared_input.wav` in the
job output directory and passes that exact file to both engines, regardless of
which engine runs first. This gives the two recognizers the same decoded,
resampled audio instead of performing two independent conversions. The file is
regenerated for each new job (there is no cross-run cache), retained on success
because the result's `normalizedAudioPath` and project metadata refer to it,
and cleanup is attempted when preprocessing fails or is cancelled. Standalone adapter calls
still normalize their own input when no normalized path is supplied.

This intentionally preserves FFmpeg's existing audio-stream selection
behavior. Explicit multi-track selection is a separate product decision and
should be validated against real multi-track files before changing the policy.
Identical shared input removes preprocessing differences as a confounder; it
does not itself prove improved lyric recall, WER, or timestamp accuracy.

**Current Windows RTX 5080 profile: Whisper is the primary transcript; Qwen3-ASR
1.7B CUDA/BF16 is the independent second opinion.** This is a quality-first
interim default based on the observed Roadhouse Blues end-to-end failure and the
fact that the existing merge path favored Qwen rows even when Whisper heard
extra lines. It is not a claim that Whisper is universally more accurate. The
profile can be reconsidered after a manually reviewed song corpus compares both
engines on the same normalized input.

The merger now checks unmatched secondary output in both directions. Lines found
only by the secondary engine are inserted in timestamp order at confidence no
higher than 60, so they are visible in the editor's review queue rather than
silently discarded or trusted as ground truth. Existing per-line alternatives
are remapped to their post-insertion row indices to avoid offering a candidate
for the wrong lyric row.

## Why full-song Whisper second opinion

The first implementation idea was to invoke Whisper only for already-suspicious
Qwen segments.

For Highest Quality mode this has two weaknesses:

1. a semantic Qwen error can still look structurally normal and therefore avoid
   the heuristic trigger;
2. repeatedly starting Whisper for small slices reloads the fallback model and
   can be slower than one full-song pass on a high-end GPU.

Highest Quality mode runs one full-song pass for each engine, then compares
their timed results by time overlap. On the Windows RTX 5080 profile Whisper is
currently primary; the Intel Mac profile already uses Whisper primary. A
secondary-only line is treated as a review-required suggestion, not as verified
lyrics. This avoids dropping all evidence from the second recognizer merely
because it did not overlap a primary row.

## Qwen native runtime contract

Elysium Player does not call Python from the Flutter UI and does not make Python a
required application runtime.

The current Qwen provider expects a local native executable compatible with this
command shape:

```text
qwen3-asr
  --device cuda
  --dtype bf16
  serve
  --model <Qwen3-ASR-1.7B model path>
  --host 127.0.0.1
  --port <ephemeral local port>
  --forced-aligner <Qwen3-ForcedAligner-0.6B model path>
```

The sidecar must provide:

```text
GET /healthz
POST /v1/transcribe
POST /v1/align
```

The currently evaluated reference implementation is the Rust/Candle
`qwen3-asr-rs` CLI. It splits long audio into chunks and offsets the timestamps
back to the original song timeline. Two limits in
`qwen3_asr/src/inference/utils.rs` matter:

- `MAX_ASR_INPUT_SECONDS = 1200` applies only to requests **without**
  timestamps.
- Elysium Player always asks for timestamps. That path
  (`transcribe_with_forced_aligner`) cuts the audio into chunks of
  `chunk_max_sec`, at most `MAX_FORCE_ALIGN_INPUT_SECONDS = 180`, choosing a
  quiet 100 ms window near each cut. It decodes every chunk on its own and
  aligns each chunk's text with the forced aligner.

An earlier revision of this document said the runtime used 1200 s chunks for
Elysium Player's requests. That was wrong, and the token budget built on it let a
looping chunk fill most of a song (D-024).

### Chunk length, token budget and context (D-024)

Elysium Player sends `chunk_max_sec = 30`. Decoding is greedy with no repetition
penalty. The runtime's own guard only catches a pattern of up to 20 characters
repeated 20 times or more, so a decoder that starts cycling through a couplet
keeps going until the chunk's budget runs out. The forced aligner then spreads
the repeated text over whatever audio the chunk covers, sung or not. Short
chunks keep such a loop inside 30 seconds. They also restart the decoder
often, so it has less chance to drift into the loop at all.

`max_new_tokens` is a **per-chunk** budget, so it is sized for one chunk:

```text
max_new_tokens = max(256, 128 + min(audio_seconds, chunk_seconds) * 8)
```

That gives 368 tokens for any song at 30 s chunks, and at most 1568 tokens at
the 180 s cap. Eight tokens per second covers roughly five CJK characters per
second with headroom. The old formula, `max(1024, 256 + min(audio_seconds,
1200) * 8)`, gave a four-minute song 2176 tokens per chunk. That was room for
several minutes of repeated lines.

The applied value is recorded as `maxNewTokens` in the document metadata,
together with these fields:

- `qwenChunkSeconds`.
- `qwenChunkFallback`, when the retry below ran.
- `qwenContextTerms`.
- `transcriptCoverage`: the fraction of the audio the recognised lyrics reach.

**Context.** Only the recognition terms the user entered for the project are
sent: proper nouns, comma-separated, at most 12, each at most 32 characters.
Title, artist and album are never sent. Over instrumental chunks Qwen copies its
context into the transcript, for example "Song title: Fire Inside. Artist:
Ridgway." over a guitar solo, and the aligner places those words where nobody
sings. A song whose title is its hook then shows the title line again and again.

**Punctuation-only chunks.** A chunk that decodes to punctuation only can be a
sub-second tail, or a lone "." over an instrumental. The pinned runtime's
aligner then fails the whole request with HTTP 500 "tokenized word_list is
empty". Runtimes from `asr-runtime-v4` apply
`tool/patches/qwen3-asr-skip-unalignable-chunks.patch`, which skips such
chunks the same way empty ones are skipped. With older runtimes, Elysium Player
retries once with 180 s chunks, which cut the song at different points.

Measured on CC-licensed songs from JamendoLyrics with reference line timing,
this setup had the lowest word error rate of the configurations tried, for both
model sizes. Dropping the title and artist cut the words placed outside sung
lines by a quarter or more. The old 2176-token budget had not finished the same
songs after three hours on CPU. The numbers are in the D-024 work log entry.

### Words the aligner could not place (D-025)

The Qwen3 forced aligner returns words it cannot place with **zero length**,
all at one instant, and stretches the next word over the singing it skipped.
These are typically a chant the recogniser wrote several times. The end of
Ridgway's "Fire Inside" (1.7B) shows the pattern:

```text
223.445–223.445  Whoa I'm paddling on I'm paddling strong Whoa find the fire find the
223.445–247.925  fire
```

The parser used to drop every word with `end <= start`. On the twelve D-024
recognitions that was 12–53 % of the recognised words per song, most of them
in repeated outro chants. The editor showed one 24-second "fire".

`AlignerWordTimingRepair` keeps them:

- A **cluster** is consecutive words that start within 30 ms of each other,
  each one zero-length except possibly the last. It is spread over the
  cluster's span in proportion to each word's letters.
- If the span is longer than 1.2 s per word, the cluster goes at the **end** of
  the span. The skipped singing came at the end of the stretched word in every
  measured case.
- If the span is shorter than 80 ms per word, it is extended towards the next
  word's start. The extension is at most 350 ms per word and never passes the
  next word.
- If there is no room at all, the words stay zero-length, but their text still
  reaches the draft.

Segment-level timestamps still need a length to become a row.

Measured on the same twelve recognitions, the word error rate of what the
editor shows fell from 0.562 to 0.437 (0.6B) and from 0.548 to 0.383 (1.7B).
The D-024 figures were computed from the raw JSON text, so they did not include
the dropped words.

Drafts recognised before this change cannot get those words back without
re-recognising. The proofreading menu's **漏唱和声检查** (missed-repeat check)
points at where they probably were. It flags three things: rows with five or
more words at one instant, words stretched to 6 s or more, and long silent
stretches after a chant near the end of the song.

Request body:

```json
{
  "audio": "C:/path/to/input.wav",
  "language": "English",
  "return_timestamps": true,
  "max_new_tokens": 368,
  "chunk_max_sec": 30,
  "max_batch_size": 4,
  "bucket_by_length": true,
  "context": "Avercage, Peyote"
}
```

The language field is omitted for automatic language detection, and `context`
is omitted when the project has no recognition terms.

The reference server returns `{"results":[...]}`. Elysium Player unwraps the
first result and accepts timestamp layouts including:

- `timestamps.items` (the current Rust/Candle forced-aligner shape)
- `segments`
- `words`
- `time_stamps`
- `timestamps.segment`
- `timestamps.words`

Each item must contain text/word plus start/end seconds.

This contract currently matches the native Rust/Candle Qwen3-ASR sidecar that
was evaluated during implementation. The contract is deliberately isolated so a
future native backend can replace it without changing project workflow or UI.

The lyric editor can optionally call `POST /v1/align` during ASR-first proofreading. It uses the same managed Qwen process, normalizes the selected vocal/original audio to 16 kHz mono WAV, and feeds validated spans into review-only token evidence. The review dialog reports incomplete coverage or runtime unavailability; neither outcome writes aligned timestamps into the source document. This option requires a runtime bundle built with the forced-alignment endpoint.

## Sidecar lifetime and GPU memory

The Qwen model and aligner stay loaded after a successful transcription so that
multiple songs can be processed without repeatedly reloading several gigabytes
of weights.

To avoid permanently reserving GPU memory, Elysium Player automatically shuts down
the Qwen sidecar after 10 minutes of inactivity. Cancellation also terminates
the sidecar immediately.

## Qwen line construction

When the forced aligner returns segment timestamps, Elysium Player uses them
directly.

When only word/character timestamps are returned, Elysium Player groups them into
editable lyric lines using:

- punctuation boundaries
- pauses of roughly 650 ms or longer
- line duration limits
- line length limits

The forced aligner remains the timing authority.

## Independent-engine comparison

Whisper output is first compared with Qwen lines inside a small timestamp
padding window. **Time overlap alone is not considered proof that the lines
correspond.** A secondary line is marked as covered only when normalized text
is equal, a contained fragment's timestamps fit its likely position or a
shared segment edge, lexical similarity is high enough over strong temporal
overlap with comparable segment durations, or both boundaries are close enough
to indicate an alternative hypothesis for the same segment. Novel secondary lines
that occur inside a long primary interval are retained as low-confidence review
rows. This is deliberately recall-oriented: the extra row is evidence to review,
not a claim that the secondary engine is correct.

Text disagreement is measured with normalized Unicode character-level
Levenshtein similarity so the same comparison path works for:

- English
- Chinese
- Japanese

A line is prioritized for review when:

- Qwen confidence is below the configured threshold;
- timing looks abnormal;
- repeated-token/hallucination heuristics trigger;
- Qwen and Whisper text similarity is low.

Only the highest-risk lines up to the configured per-song review limit are
stored as fallback candidates.

## Conservative automatic replacement

Whisper automatically replaces Qwen text only when the primary line is clearly
unreliable, for example:

- suspicious repetition in Qwen but not Whisper; or
- very low Qwen confidence plus materially stronger Whisper confidence.

The Qwen ForcedAligner timestamps are preserved even when Whisper text is
selected.

Other disagreements remain visible in the lyric editor as a Whisper candidate
with an explicit “use alternative” action.

## Re-running one stretch

The editor's proofreading menu can re-run a few rows instead of the whole
song (重新识别这一段, D-026). `ProjectSpanRecognitionService` cuts the
stretch into its own 16 kHz mono clip with FFmpeg, runs it through Qwen3-ASR
(on the app's shared adapter, so a model still loaded from a full run is
reused), Whisper, or the forced aligner, and moves the result back onto the
song's timeline. It holds the shared ASR resource lease
(`AsrResourceUse.spanRecognition`) for the whole run and never writes the
project; the editor previews the result and applies it as one undoable edit.

- The stretch is 0.5–90 s. It reaches 0, 0.5, 1 or 2 s past the chosen rows,
  or up to the neighbouring row, but never into it.
- Recognised rows are clipped to the stretch, ordered and de-overlapped;
  fragments shorter than 120 ms after clipping are dropped.
- Re-alignment keeps the rows' text and fails closed: any word that does not
  match the rows in order discards the whole result.

## Whisper loops across segments (D-027)

whisper.cpp decodes in 30 s windows and, by default, conditions each window
on up to 224 tokens of the text it already decoded. On songs this lets a
repeated couplet feed itself: once one window repeats it, every later window
sees it in its prompt, and the rest of the song becomes the same one or two
lines on a collapsed one-second timestamp grid. Each looped row is an
ordinary-looking line, so per-line checks never saw it, and the fusion step
used to keep it or insert it row by row as a suggestion.

- **Prevention:** the `lyrics` profile (`whisper-lyrics-v2`) runs with
  `--max-context 0` and no prompt. Measured on six JamendoLyrics songs with
  large-v3, mean WER dropped from 0.815 (v1) and 0.687 (standard) to 0.354,
  with no block loop left.
- **Recovery:** when a run kept the history (the `standard` profile, or a
  runtime that rejected the flag) and its output loops strongly,
  `WhisperLoopRecoveryPolicy` decodes only the looped stretch again with
  `--offset-t/--duration --max-context 0` and splices the result in unless
  that loops too (`whisperLoopRecovery` metadata).
- **Arbitration:** in Highest Quality, `WhisperLoopArbiter` compares every
  remaining Whisper loop with what Qwen (which decodes 30 s chunks with no
  carried text) heard over the same audio. Qwen hears distinct lines → its
  rows replace the loop and are queued for review; Qwen hears the same
  repetition → kept; no usable Qwen rows → a strong loop is cut to one
  repetition and flagged, a weak one or a short chant is only flagged
  (`whisperLoopArbitration` metadata, review candidates with
  `whisper_cross_segment_*` reasons).
- `AsrSegmentLoopDetector` finds the loops: one row at least 3 times, or a
  block of 2–4 rows at least 3 times; strong at 6 rows / 4 blocks, or when
  most looped rows hold more than 7 words (CJK characters) per second.

## Lyric editor behavior

The editor now surfaces:

- low-confidence warning state
- confidence score
- whether Whisper was automatically selected
- alternative Whisper text when Qwen remains selected

A manual text edit is treated as user confirmation for that line and raises the
line confidence to 100.

The Qwen response can provide timestamped text without calibrated lexical
confidence. In that case the adapter uses a neutral score of 50 rather than the
old optimistic score of 92, which was inferred from timestamp/text shape and
could make severely misrecognized lines look trustworthy. This score is a
review-priority signal, not a calibrated probability. Explicit model-provided
scores are still retained when available.

Structural edits such as adding or deleting lines clear stale fallback index
metadata.

## Current runtime configuration

Highest Quality mode currently requires local runtime configuration for:

- native CUDA-enabled `qwen3-asr` runtime
- Qwen3-ASR 1.7B model reference
- Qwen3 ForcedAligner 0.6B model reference
- whisper.cpp runtime
- Whisper large-v3 model
- FFmpeg

The Qwen model fields can use the official Hugging Face IDs directly:

- `Qwen/Qwen3-ASR-1.7B`
- `Qwen/Qwen3-ForcedAligner-0.6B`

The native sidecar downloads/caches those models on first use, so a separate
manual model-directory setup is not required.

For the current high-end target machine, Qwen uses:

- device: `cuda`
- dtype: `bf16`

A later productization phase can add automatic model/runtime installation for
general users without changing the transcription architecture.

## Automatic vocal separation (D-043)

Highest Quality ASR prefers `AudioAsset.vocalPath`. On Windows x64 the
project workflow now produces that stem itself before recognition:

- `lyricforge-separator` (`native/vocal_separator`) runs the fine-tuned
  htdemucs vocals model exported to ONNX on ONNX Runtime, DirectML first
  (any DirectX 12 GPU, the RTX 5080 target included) and CPU as fallback;
- the bundle (`lyricforge-vocal-separator-windows-x64.zip`, release
  `vocal-separator-v1`, built by `build-vocal-separator.yml`) is installed on
  first use and verified against the release digest and its manifest;
- the stem is linked as `vocalPath` with a provenance marker and reused
  while the song file and separator revision are unchanged;
- an imported vocal stem always wins, and every failure (no release yet, no
  GPU, a decode error, a near-silent stem from an instrumental) falls back
  to the mix and is recorded in `metadata.transcription.vocalSeparation`.

Separation is a setting (`TranscriptionConfig.vocalSeparation`, on by
default). Other platforms keep recognising the imported stem or the mix.

## Vocal check on the separated stem (D-044)

A separated vocal stem is close to silent wherever nobody sings, which the
mix never is. After recognising a stem (automatic, reused, or imported) the
project workflow checks the fresh draft against it:

- `PcmWavEnergyReader` reads the loudness in 20 ms frames from recognition's
  own 16 kHz mono copy (or the 44.1 kHz stereo stem), off the UI isolate;
- `VocalActivityAnalyzer` finds the sung stretches with song-relative
  thresholds (within 30 dB of the 95th percentile, above the quiet between
  phrases, never below -55 dBFS), bridges breaths under 250 ms and drops
  blips under 100 ms; a stem whose loud and quiet frames are less than
  18 dB apart (a full mix imported as the vocal, heavy bleed) is reported as
  unreliable and nothing changes;
- `VocalActivityLyricGate` deletes rows with less than 150 ms of singing
  (±200 ms) — the invented intro, interlude and outro lines — unless more
  than 35 % of the rows (and more than three) look silent, which points at a
  shifted timeline instead; pulls row starts that lead into 0.4 s or more of
  silence, and ends that trail 0.6 s or more, onto the singing without
  crossing word timing or touching rows only the second engine heard; and
  records stretches of singing with no row as probably missed lyrics.

The document keeps the record (`metadata.vocalCheck`: removed rows with
their text and times, retimed count, uncovered stretches) and the run keeps
the report (`metadata.transcription.vocalCheck`). The editor's recognition
summary shows the stretches that still have no lyrics, with times, until a
row covers them. Drafts recognised from the mix are not checked.

### One-click follow-ups (D-045)

The record is also what the editor acts on:

- every listed stretch of singing without lyrics has a button on the
  recognition summary ("识别 m:ss.s"; with more than three stretches, a
  walk-through button). It opens a dialog that immediately recognises the
  stretch, padded by 0.3 s on each side but never into the neighbouring
  rows, with Qwen3-ASR (Whisper is one click away and re-runs at once);
  the recognised rows are clipped to that window and inserted as new rows,
  leaving every existing row untouched. A stretch that is humming or a
  sample can be marked "这里没有歌词" instead, which removes it from the
  record (`dismissedSpans` counts them). Stretches squeezed under 0.5 s or
  over 90 s are not sent;
- rows the check deleted can be restored all at once ("全部恢复") or after
  reviewing them with a checkbox each ("逐行查看", with a preview of the old
  time). Restored rows go back at their recognised times, are protected like
  hand edits, and leave the record (`restoredLines` counts them).

Both are single undoable edits and are also in the proofreading menu
(`LyricVocalCheckActions` plans them; nothing is written until saving).

## Arbitrary-text ForcedAligner boundary

The official Qwen3-ASR Python API exposes `Qwen3ForcedAligner.align(audio, text, language)`, returning item-level text and start/end seconds. That is a real arbitrary-text alignment API, but it is a Python library call, not evidence that every server wrapping the model exposes the same request contract.

Elysium Player's currently pinned Rust/Candle sidecar is launched with `--forced-aligner` and the app calls `POST /v1/transcribe`. That request accepts audio and transcription options; it does not send the supplied lyric text as an alignment target. The existing timestamps therefore describe ASR output, not an arbitrary reference lyric aligned on demand. Do not use the `context` field as a substitute.

The repository now carries a patch against the pinned Rust/Candle source that adds `POST /v1/align` with explicit `audio`, `text`, and `language` inputs. It calls the loaded `Qwen3ForcedAligner.align` API directly and returns `results[0].items` with `text`, `start_time`, and `end_time` in seconds; it does not route through ASR `context`. The native build workflow applies the patch for Windows CUDA and macOS Intel bundles and runs an endpoint contract integration test. Until that native CI passes and a rebuilt bundle is installed, existing downloaded runtime binaries must still be treated as lacking this endpoint.

The Dart HTTP adapter validates timestamp ordering and audio-duration bounds. Zero-length spans (words the aligner could not place) are repaired with `AlignerWordTimingRepair.repairToTimedSpans` instead of failing the request: clusters are spread where there is room, and a word still without length is merged into its neighbour, so text and order are preserved (D-026). `ForcedAlignmentProofreadService` now passes explicit audio path, reference text, and language to `/v1/align`, then maps the returned spans into the ASR-first proofread proposal as review-only tokens. Incomplete line coverage returns a warning; request/runtime errors fall back to the ordinary proposal with a visible `forcedAlignmentUnavailable` note. Neither success nor failure edits source lyric text or timestamps. The native endpoint contract CI has passed, but existing installed runtime bundles still need rebuilding before they expose `/v1/align`; real-song accuracy and Chinese/English/Japanese coverage remain unverified.


## Forced-alignment evidence in proofreading proposals

The ASR-first proofread pipeline accepts validated alignment spans and attaches them to matching review rows as `TimedLyricToken` evidence. It normalizes alignment text with the shared Unicode-aware lyric tokenizer, including full-width Latin forms, CJK characters, and common Chinese/Japanese punctuation, then matches contiguous span text against each draft line in source order. The matcher can recover across up to 12 unmatched spans before a line and considers at most 128 spans for a single line candidate; consumed spans are never reused, and a failed row does not automatically block later rows from matching. These are hard safety bounds, not permission to guess. The domain result carries `ProofreadAlignmentDiagnostics` with total/matched line counts, line coverage, skipped span count, and unmatched line indices (zero-based in the model). The service marks alignment as requested even when a successful response contains zero spans, so the result reports zero coverage rather than silently treating the response as “not requested”. Incomplete diagnostics produce a warning with line coverage, skipped-span count, and one-based unmatched lyric row numbers. The review dialog displays those diagnostics in a dedicated summary block; an empty successful response therefore shows zero coverage and does not claim that token evidence was produced. Skipped spans are not automatically classified as noise or ad-libs. The original lyric text and line-level timestamps remain unchanged. The current `/v1/align` response provides token text and start/end times but no calibrated confidence score, so `TimedLyricToken.confidence` is `null` for ForcedAligner evidence. Do not infer model confidence from the presence or duration of a span. Contract tests cover English, full-width Latin, Chinese, Japanese text normalization, bounded recovery, repeated lines and diagnostics invariants, but synthetic spans do not prove actual audio timing accuracy; real-song coverage still requires a rebuilt runtime bundle and manual audio validation.


## Repeatable transcript comparison across ASR engines

Use the transcript evaluator to compare Whisper, Qwen, and the fused draft against
the **same manually verified reference text for the same audio clip**:

```powershell
dart run tool/asr_transcript_eval.dart docs/evaluation/asr_transcript_corpus.json --output build/asr_transcript_report.json
```

Corpus schema version 1:

```json
{
  "schemaVersion": 1,
  "samples": [
    {
      "id": "road-house-blues-en-01",
      "songId": "roadhouse-blues",
      "language": "English",
      "referenceText": "Manually checked lyrics for this exact clip",
      "candidates": [
        { "engine": "whisper-large-v3", "text": "Whisper output" },
        { "engine": "qwen3-asr-1.7b", "text": "Qwen output" },
        { "engine": "highest-quality-fusion", "text": "Fused output" }
      ]
    }
  ]
}
```

The report calculates normalized character error rate (CER), tokenizer-level
error rate, and word error rate (WER) where meaningful; it also aggregates by
engine and language. Normalization lowercases text, normalizes full-width forms,
and ignores punctuation and whitespace. WER is `null` for a candidate/reference
pair containing CJK characters because the shared tokenizer deliberately
tokenizes CJK one character at a time; use CER and token error rate for Chinese,
Japanese, Korean, or mixed-script clips. Aggregate rates are weighted by total
reference units and error counts rather than averaging per-song percentages.
Empty ASR output counts as a complete omission and is not silently excluded.

Every candidate in a sample must come from the same audio clip and preprocessing
path; otherwise the comparison is confounded. Reference lyrics must be manually
checked for the sung words, repeated sections, and backing vocals/ad-libs that
the benchmark intends to count. Do not treat web lyrics that omit performed
words as a gold reference.

This transcript tool does not assess timestamps or line segmentation. Use
`tool/forced_alignment_eval.dart` with manually checked reference intervals to
measure span recall, unmatched spans, and boundary error separately. No real-song
accuracy claim should be made from synthetic unit tests alone.

## Paired preprocessing A/B evaluation

Run this comparison to evaluate the previous per-engine conversion path against
Highest Quality mode's shared normalized WAV, without mixing clips, references,
or model/runtime versions:

    dart run tool/asr_preprocessing_ab_eval.dart "D:/Evaluation/asr-baseline-corpus.json" "D:/Evaluation/asr-shared-input-corpus.json" --output "D:/Evaluation/asr-preprocessing-ab-report.json"

Both corpora use schema version 1 and must include the strict fields already
required by the transcript evaluator. Add `sourceAudioSha256` to each sample;
this is the SHA-256 of the original input file before preprocessing. The
existing `audioSha256` remains the hash of the exact normalized WAV bytes
supplied to the candidate engine.

For the baseline, create one sample row per engine when their normalized WAV
hashes differ. Those rows should share the same `songId`, original source hash,
duration, reviewed reference text, and language, but each candidate's
`audioSha256` must match its own sample. In the shared-input corpus, one row
can contain both Qwen and Whisper candidates because they should use the same
WAV hash. Use stable engine identifiers across both corpora.

The A/B tool refuses to compare data if the pair sets differ, the source file,
reference text/review flag, language or duration changes, a candidate is missing
strict provenance, or any engine's model revision/runtime version differs. It
reports character/token edit rates and insertion/deletion/substitution deltas
per engine and clip. Negative error-rate deltas mean fewer errors in the shared
run. WER is reported only for a paired candidate when both runs support WER;
for example, if one transcript contains CJK characters and the other does not,
the pair is excluded from both sides' WER aggregation. The report also checks
whether the actual normalized WAV hashes changed.
If they are all identical, `preprocessingEffectTestable` is false and a warning
explains that the run cannot isolate an audio-byte change.

Begin with Qwen and Whisper transcript outputs; do not attribute fusion changes
to preprocessing unless the baseline fusion candidate has a valid, unambiguous
input fingerprint. This tool does not read local audio or invent reference
lyrics. Synthetic tests validate only the comparator; measured results require
real audio, manually checked lyrics, actual input hashes, and pinned versions.

## Repeatable ForcedAligner quality evaluation

A small corpus of manually checked token intervals can be used to compare captured `POST /v1/align` spans against reference times. The evaluator reports normalized-text recall/precision, unmatched reference/output spans, mean/median/p95/max absolute boundary error, and the rate of boundaries within a configured tolerance. Results are grouped overall and by language.

```bash
dart run tool/forced_alignment_eval.dart docs/evaluation/forced_alignment_corpus.json --output build/forced_alignment_report.json
```

The corpus uses schema version 1, a non-empty `samples` array, unique sample IDs, language names, optional `audioDurationMs`, and `referenceSpans`/`actualSpans` arrays. Each span contains `text`, integer `startMs`, and integer `endMs`. Optional settings are `toleranceMs` (default 150) and `maxGroupSpans` (default 8). Ordered bounded matching accepts different span grouping without inventing intermediate timestamps.

**Important:** no real audio or fabricated gold data is shipped with this tool. Reference intervals must be manually checked against the same original audio; synthetic tests validate the evaluator logic only. Keep separate Chinese, English, and Japanese samples and include repetitions/ad-libs before setting quality thresholds.

## Capture real local ForcedAligner results

The evaluator has a `capture` subcommand that calls a local `POST /v1/align`
endpoint, stores the returned spans as `actualSpans`, and converts
`start_time`/`end_time` seconds to integer milliseconds. It only accepts a
loopback host (`localhost`, `127.0.0.1`, or another loopback IP) and the exact
`/v1/align` path; lyrics and local file paths are never sent to an arbitrary
remote service.

Prepare a UTF-8 text file containing the exact lyric text sent to the aligner,
and a separate JSON file of manually checked reference intervals. The reference
file may be a JSON array or an object with a `referenceSpans` array:

```json
[
  { "text": "hello", "startMs": 1250, "endMs": 1510 },
  { "text": "world", "startMs": 1540, "endMs": 1850 }
]
```

Start a rebuilt local native runtime on a known loopback port, then capture the
first sample from PowerShell:

```powershell
dart run tool/forced_alignment_eval.dart capture `
  --endpoint http://127.0.0.1:8000/v1/align `
  --audio "D:/Songs/example.wav" `
  --text-file "D:/Songs/example.txt" `
  --reference "D:/Songs/example-reference.json" `
  --id en-example-01 --language English `
  --duration-ms 214000 `
  --output "D:/Evaluation/forced_alignment_corpus.json"
```

For the next song, keep the same corpus and use `--append-to` instead of
`--output`:

```powershell
dart run tool/forced_alignment_eval.dart capture `
  --endpoint http://127.0.0.1:8000/v1/align `
  --audio "D:/Songs/chinese-song.wav" `
  --text-file "D:/Songs/chinese-song.txt" `
  --reference "D:/Songs/chinese-song-reference.json" `
  --id zh-example-01 --language Chinese `
  --duration-ms 198000 `
  --append-to "D:/Evaluation/forced_alignment_corpus.json"
```

The tool validates sample IDs, span order and duration bounds before writing. It reserves a new output path exclusively and refuses to overwrite an appended corpus that changed during alignment.
An empty `items` array is preserved as an empty actual result so evaluation can
report zero recall instead of hiding a failed alignment. Reference intervals
must be manually checked against the same audio file; this workflow does not
claim model accuracy until the corpus has been reviewed and evaluated.

## Interpreting transcript edit breakdowns

The paired transcript evaluator reports not only the minimum edit count and
normalized error rates, but also the operation counts for characters and shared
lyric tokens. The edit script transforms the reference into a candidate:

- **Insertions** are extra units present only in the candidate. They can signal
  hallucinated lyrics, repeated syllables, or other excess text.
- **Deletions** are reference units absent from the candidate. They are an
  omission signal and should be checked against the audio, including ad-libs
  and backing vocals where applicable.
- **Substitutions** are reference units replaced with incorrect candidate units.

Each breakdown is one deterministic minimum-edit path; the three counts sum to
the corresponding edit count. Per-sample detail helps locate failures, while
engine/language summaries sum operation counts across samples. These are text
diagnostics, not a guaranteed semantic classification: an insertion can be a
legitimate vocalization missing from an incomplete reference, and a deletion can
reflect a reference transcription mistake. Review the audio before changing
fusion thresholds.

## Paired corpus provenance

Transcript corpus schema version 1 accepts optional provenance fields so older
corpora remain usable. For new evaluations, record these fields:

- On each sample, `audioSha256` is the SHA-256 of the exact audio bytes passed to
  the recognizers, `audioDurationMs` is the duration in milliseconds, and
  `referenceReviewed: true` means a person has checked the reference against
  the sung audio.
- On every candidate, `audioSha256` records the actual model input fingerprint.
  If present, it must match the sample fingerprint; a mismatch stops evaluation.
- `modelRevision` and `runtimeVersion` identify the model and inference
  runtime used for that output. Keep the engine name stable across the corpus.

On Windows, compute a fingerprint for the normalized clip you actually pass to
both engines:

```powershell
(Get-FileHash -Algorithm SHA256 "D:/Evaluation/clip.wav").Hash.ToLowerInvariant()
```

Use that same fingerprint on the sample and each candidate only when they
consumed the exact same file bytes. If preprocessing differs, do not copy the
fingerprint across those outputs: normalize them to the same input first or
treat them as separate samples. The evaluator does not hash local audio itself
and does not upload audio or lyrics.

Legacy corpora without these fields still produce metrics, but the report adds
a `provenance` section listing missing fingerprints, durations, explicit
reference-review status, model revisions, runtime versions, and warnings. Use
this section to judge whether a comparison is reproducible before making model
or fusion decisions. A SHA-256 fingerprint identifies exact bytes; it does not
prove that the reference text itself is correct.

## Strict provenance gate for transcript evaluation

The default evaluator remains backwards-compatible: incomplete provenance is
reported as warnings so existing schema v1 corpora can still be inspected. For
a benchmark run intended to support model or fusion decisions, use the strict
mode and save the report even when its metadata gate fails:

```powershell
dart run tool/asr_transcript_eval.dart "D:/Evaluation/asr-corpus.json" `
  --require-provenance `
  --output "D:/Evaluation/asr-report.json"
```

Strict mode requires every sample to record its exact audio SHA-256, positive
duration, and `referenceReviewed: true`; every candidate must record the same
audio SHA-256, a model revision and a runtime version. A metadata-incomplete run
still writes the diagnostic report and exits with code 2, allowing scripts to
stop a benchmark pipeline without losing the list of missing fields. A complete
run exits successfully. This gate validates declared provenance completeness,
not the truth of the human review or the recognizer's actual input handling.

## Strict provenance gate for ForcedAligner evaluation

ForcedAligner benchmarking uses a paired reference-span corpus: its reference
spans must be checked against the original audio, while the actual spans must
come from the exact audio file being identified. The capture command computes
the input file's SHA-256 before sending its path to the local `/v1/align`
endpoint and checks the hash again after the response; if the bytes change
during alignment, it refuses to write the sample. Use explicit model and runtime
identifiers so timing results can be reproduced and compared meaningfully.

Example capture command in PowerShell:

```powershell
dart run tool/forced_alignment_eval.dart capture `
  --endpoint "http://127.0.0.1:8080/v1/align" `
  --audio "D:/Evaluation/clip.wav" `
  --text-file "D:/Evaluation/reference-lyrics.txt" `
  --reference "D:/Evaluation/reference-spans.json" `
  --id "song-en-01" `
  --language English `
  --duration-ms 184320 `
  --reference-reviewed `
  --model-revision "Qwen3-ForcedAligner-0.6B@<revision>" `
  --runtime-version "qwen3-asr-rs@<version>" `
  --output "D:/Evaluation/alignment-corpus.json"
```

Only pass `--reference-reviewed` after a person has checked the lyric text
and reference timestamps against the same audio. If it is omitted, capture
records the status as unreviewed. The model/runtime values are declarations;
record the real model commit or release and runtime bundle version, not labels
chosen merely to make the gate pass.

Run the evaluator with the strict gate for results used to compare models or
decide ASR/fusion changes:

```powershell
dart run tool/forced_alignment_eval.dart "D:/Evaluation/alignment-corpus.json" `
  --require-provenance `
  --output "D:/Evaluation/alignment-report.json"
```

The report always contains a `provenance` section listing missing audio
fingerprints, durations, reference review confirmations, model revisions,
runtime versions, and warnings. In strict mode, missing metadata still produces
the diagnostic report but exits with code 2. Legacy schema v1 corpora remain
evaluable without the flag. This gate checks declared metadata completeness and
capture-time audio identity; it does not verify the truth of a human annotation
or recover the version of a model used by an old manually assembled corpus.


## ASR model identity in saved metadata

Fusion metadata and the project's saved transcription record derive engine/model
identities from the configured Qwen ASR, Qwen ForcedAligner, and Whisper model
paths. This avoids reporting a fixed Qwen 0.6B/1.7B or Whisper large-v3 label
when another variant is configured. The persisted display labels use only the
final path component, not an absolute local directory.

These identifiers describe the configured model path; they are not a content
hash and do not prove which weight bytes a runtime actually loaded. For strict
quality comparisons, retain the exact audio fingerprint and manually reviewed
reference from the evaluation corpus, and separately record the actual model
revision and native runtime bundle version.
