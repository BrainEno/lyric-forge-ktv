/// How Elysium Player chunks a Qwen3-ASR request and how many tokens each chunk
/// may decode.
///
/// The local runtime (`qwen3-asr-rs`) cuts the song into chunks at quiet
/// points, decodes every chunk on its own with greedy search and then runs the
/// ForcedAligner over each chunk's text. Two facts about that loop decide the
/// numbers below:
///
/// * Every Elysium Player request asks for timestamps, and with timestamps the
///   runtime caps a chunk at [qwenTimestampedMaxChunk] (180 s,
///   `MAX_FORCE_ALIGN_INPUT_SECONDS`), not at the 1200 s that plain
///   transcription uses. `max_new_tokens` applies **per chunk**.
/// * Greedy decoding has no repetition penalty. Once a chunk falls into a loop
///   (the last couplet over a guitar solo, the title over an interlude) it
///   keeps repeating until the token budget runs out, and the aligner then
///   spreads all of that text over the chunk — sung parts and instrumental
///   parts alike. The runtime's own repetition fix only collapses patterns of
///   up to 20 characters, so a repeated sentence passes through.
///
/// A budget sized for a 1200 s chunk (what this file used to compute) gave a
/// four-minute song about 2 200 tokens for each 180 s chunk, several times
/// what the lyrics of that chunk need, which is the room a loop needs to fill
/// the rest of the song. Real songs measured on the pinned runtime also lost
/// lines with long chunks: the decoder skips and summarises. Elysium Player
/// therefore asks for short chunks ([qwenRecognitionChunk]) and sizes the
/// budget for one of them, so a loop can only fill one short chunk.
library;

/// Longest chunk the runtime decodes when timestamps are requested.
///
/// Mirrors `MAX_FORCE_ALIGN_INPUT_SECONDS = 180.0` in `qwen3-asr-rs`
/// (`qwen3_asr/src/inference/utils.rs`); a larger `chunk_max_sec` is clamped
/// to it by the runtime.
const Duration qwenTimestampedMaxChunk = Duration(seconds: 180);

/// Chunk length Elysium Player asks the runtime for (`chunk_max_sec`).
///
/// Thirty seconds is the window Whisper was trained on and the length at
/// which the pinned runtime kept the most words on the songs measured for
/// D-024; the runtime still moves each cut to the quietest point within a few
/// seconds of it.
const Duration qwenRecognitionChunk = Duration(seconds: 30);

/// Chunk length of the single retry when the runtime rejects a request with
/// [qwenRecognitionChunk] (see `Qwen3AsrNativeTranscriptionService`).
const Duration qwenFallbackChunk = qwenTimestampedMaxChunk;

/// Token budget per second of audio.
///
/// Dense singing tops out around five CJK characters per second and Qwen's
/// tokenizer spends at most about one token per character, so eight tokens per
/// second leaves headroom for both scripts and for punctuation.
const int qwenDecodeTokensPerAudioSecond = 8;

/// Fixed allowance per chunk for the language header and the
/// end-of-utterance marker.
const int qwenDecodeBaseTokens = 128;

/// Lower bound for very short audio.
const int qwenDecodeMinimumTokens = 256;

/// Duration of the normalized ASR input described by [wavBytes].
///
/// Normalization writes 16 kHz, mono, signed 16-bit PCM, so the payload grows by
/// a fixed number of bytes per second. The 44-byte RIFF header is excluded.
Duration normalizedPcmWavDuration(int wavBytes) {
  const headerBytes = 44;
  const bytesPerSecond = 16000 * 1 * 2;
  final payloadBytes = wavBytes > headerBytes ? wavBytes - headerBytes : 0;
  final seconds = (payloadBytes + bytesPerSecond - 1) ~/ bytesPerSecond;
  return Duration(seconds: seconds);
}

/// The chunk length the runtime will actually use for [requested]: at most
/// [qwenTimestampedMaxChunk], and at least one second.
Duration effectiveQwenChunk(Duration requested) {
  if (requested <= Duration.zero) return qwenTimestampedMaxChunk;
  if (requested > qwenTimestampedMaxChunk) return qwenTimestampedMaxChunk;
  if (requested < const Duration(seconds: 1)) {
    return const Duration(seconds: 1);
  }
  return requested;
}

/// The largest budget [qwenMaxNewTokensFor] can return: one chunk of the
/// longest length the runtime allows.
int get qwenDecodeCeilingTokens =>
    qwenDecodeBaseTokens +
    qwenTimestampedMaxChunk.inSeconds * qwenDecodeTokensPerAudioSecond;

/// Token budget for one chunk when [audioDuration] of audio is sent in chunks
/// of [chunk].
///
/// Only the first chunk's worth of audio matters: the runtime never hands the
/// decoder more than one chunk at a time, so a longer song does not need a
/// larger budget per chunk, and a larger one only gives a stuck decoder more
/// room to repeat itself.
int qwenMaxNewTokensFor(
  Duration audioDuration, {
  Duration chunk = qwenRecognitionChunk,
}) {
  final chunkSeconds = effectiveQwenChunk(chunk).inSeconds;
  final effectiveSeconds = audioDuration.inSeconds <= 0
      ? 0
      : audioDuration.inSeconds.clamp(0, chunkSeconds).toInt();
  final derived =
      qwenDecodeBaseTokens + effectiveSeconds * qwenDecodeTokensPerAudioSecond;
  return derived < qwenDecodeMinimumTokens ? qwenDecodeMinimumTokens : derived;
}

/// Convenience for the common case: the budget for a normalized WAV file.
int qwenMaxNewTokensForPcmWav(
  int wavBytes, {
  Duration chunk = qwenRecognitionChunk,
}) => qwenMaxNewTokensFor(normalizedPcmWavDuration(wavBytes), chunk: chunk);
