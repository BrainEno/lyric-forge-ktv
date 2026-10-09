# Lyric export format

LyricForge uses the project manifest and `LyricDocument` as the authoritative editable lyric timeline. For interoperable user export, the canonical format is **UTF-8 LRC**.

## Canonical LRC profile

- Encoding: UTF-8 without BOM.
- Line ending: `\n`.
- Timestamp: `[mm:ss.SSS]`, using three millisecond digits.
- Each exported lyric row contains one start timestamp followed by lyric text.
- Rows are sorted by `LyricLine.startTime` before export.
- Embedded line breaks in one lyric row are normalized to a single space.
- Blank lyric rows are not exported.
- Exported timestamps are the final playback timestamps: `max(0, LyricLine.startTime + LyricDocument.globalOffset)`.
- LyricForge does **not** write an LRC `[offset]` tag. Different players disagree about the sign/direction of that optional field and some ignore it entirely. Baking the correction into each timestamp makes exported playback deterministic.

The project manifest still keeps `globalOffset` separate from every line, so users can continue to adjust one global correction non-destructively while editing.

## Metadata

LyricForge writes these tags when the information is available:

```text
[ti:Song title]
[ar:Artist]
[al:Album]
[lang:zh]
[re:LyricForge]
[ve:1]
```

## Example

For a project whose editable line starts are `00:03.456` and `00:07.123` with a `+80 ms` global offset, LyricForge exports:

```text
[ti:Demo Song]
[ar:Demo Artist]
[lang:zh]
[re:LyricForge]
[ve:1]
[00:03.536]你好吗
[00:07.203]I am fine
```

This means the standalone LRC already contains the same timing the user heard in LyricForge.

## Precision and compatibility

Classic LRC commonly uses centisecond timestamps such as `[mm:ss.xx]`. LyricForge emits the compatible high-precision form `[mm:ss.SSS]` so millisecond ASR/manual timing is not needlessly rounded. Consumers that support high-precision/enhanced LRC retain the full value; the LyricForge project remains the authoritative production master regardless of what a third-party player displays.

## Information retained only by the project manifest

Classic LRC is a start-time lyric format. It does not reliably preserve all LyricForge editing data. The project manifest remains the source of truth for:

- exact `endTime`
- separate `globalOffset`
- `confidence`
- `isChorus`
- transcription review/fallback metadata
- future word-level or phoneme-level timing data

When an exported LRC is imported again, line end times are inferred from the next line start (or a fallback duration for the final line), and the already-applied global offset is flattened into the imported line timestamps. The re-imported lyrics therefore keep equivalent playback alignment, but they do not reconstruct the original line-time/offset decomposition. Use the LyricForge project as the lossless editable master and LRC as the interoperable playback export.
