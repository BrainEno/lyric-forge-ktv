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
- The exported timestamp is the unshifted `LyricLine.startTime`.
- `LyricDocument.globalOffset` is exported separately through `[offset:<milliseconds>]`. This keeps the editable line timeline and global playback correction separable and allows a lossless start-time/offset round trip.

## Metadata

LyricForge writes these tags when the information is available:

```text
[ti:Song title]
[ar:Artist]
[al:Album]
[lang:zh]
[re:LyricForge]
[ve:1]
[offset:-120]
```

`offset` is omitted when it is zero. Positive values delay lyric display; negative values advance it, matching the application's playback timeline semantics.

## Example

```text
[ti:Demo Song]
[ar:Demo Artist]
[lang:zh]
[re:LyricForge]
[ve:1]
[offset:80]
[00:03.456]你好吗
[00:07.123]I am fine
```

## Information retained only by the project manifest

Classic LRC is a start-time lyric format. It does not reliably preserve all LyricForge editing data. The project manifest remains the source of truth for:

- exact `endTime`
- `confidence`
- `isChorus`
- transcription review/fallback metadata
- future word-level or phoneme-level timing data

When an exported LRC is imported again, line end times are inferred from the next line start (or a fallback duration for the final line). Therefore LRC is intended for playback interoperability, while the LyricForge project remains the editable production master.
