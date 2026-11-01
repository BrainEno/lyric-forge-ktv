/// Decode budget for one Qwen3-ASR request.
///
/// The local runtime splits long audio into chunks of at most
/// [qwenRuntimeMaxChunk] (`MAX_ASR_INPUT_SECONDS` in `qwen3-asr-rs`) and applies
/// `max_new_tokens` **per chunk**, not per file. A single fixed budget therefore
/// has to cover a full chunk of audio; the previous constant (1024) covered
/// roughly two minutes of dense lyrics and could silently truncate the end of a
/// song while still returning HTTP 200.
library;

/// Longest single chunk the local runtime will process.
///
/// Mirrors `MAX_ASR_INPUT_SECONDS = 1200.0` in `qwen3-asr-rs`
/// (`qwen3_asr/src/inference/utils.rs`).
const Duration qwenRuntimeMaxChunk = Duration(seconds: 1200);

/// Token budget per second of audio.
///
/// Dense singing tops out around five CJK characters per second and Qwen's
/// tokenizer spends at most about one token per character, so eight tokens per
/// second leaves headroom for both scripts and for punctuation.
const int qwenDecodeTokensPerAudioSecond = 8;

/// Fixed allowance for the chat-style header and the end-of-utterance markers.
const int qwenDecodeBaseTokens = 256;

/// Lower bound; equal to the value this budget replaced, so no request can end
/// up with a smaller allowance than before.
const int qwenDecodeMinimumTokens = 1024;

/// Upper bound. The runtime never hands the decoder more than
/// [qwenRuntimeMaxChunk] of audio, so the derived value tops out well below
/// this; the ceiling only protects against a caller passing an absurd duration.
const int qwenDecodeMaximumTokens = 16384;

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

/// Token budget for [audioDuration] of audio.
///
/// Only the first [qwenRuntimeMaxChunk] matter: the runtime never sends more
/// than one chunk to the decoder at a time, so a longer file does not need a
/// larger per-request budget (and asking for one would only inflate the
/// allocation without ever being used).
int qwenMaxNewTokensFor(Duration audioDuration) {
  final effectiveSeconds = audioDuration.inSeconds <= 0
      ? 0
      : audioDuration.inSeconds
            .clamp(0, qwenRuntimeMaxChunk.inSeconds)
            .toInt();
  final derived =
      qwenDecodeBaseTokens + effectiveSeconds * qwenDecodeTokensPerAudioSecond;
  return derived.clamp(qwenDecodeMinimumTokens, qwenDecodeMaximumTokens).toInt();
}

/// Convenience for the common case: the budget for a normalized WAV file.
int qwenMaxNewTokensForPcmWav(int wavBytes) =>
    qwenMaxNewTokensFor(normalizedPcmWavDuration(wavBytes));
