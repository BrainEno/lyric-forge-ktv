import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/qwen_decode_budget.dart';

/// Bytes of one second of normalized ASR audio: 16 kHz, mono, 16-bit PCM.
const int _bytesPerSecond = 16000 * 1 * 2;

int _wavBytesForSeconds(int seconds) => 44 + seconds * _bytesPerSecond;

void main() {
  group('normalizedPcmWavDuration', () {
    test('derives a duration from the normalized payload size', () {
      expect(
        normalizedPcmWavDuration(_wavBytesForSeconds(215)),
        const Duration(seconds: 215),
      );
    });

    test('ignores the RIFF header and rounds partial seconds up', () {
      expect(normalizedPcmWavDuration(44), Duration.zero);
      expect(
        normalizedPcmWavDuration(44 + _bytesPerSecond ~/ 2),
        const Duration(seconds: 1),
      );
      expect(normalizedPcmWavDuration(0), Duration.zero);
    });
  });

  group('effectiveQwenChunk', () {
    test('LyricForge asks for 30 second chunks', () {
      expect(qwenRecognitionChunk, const Duration(seconds: 30));
      expect(effectiveQwenChunk(qwenRecognitionChunk), qwenRecognitionChunk);
    });

    test('is clamped to the runtime limit for timestamped requests', () {
      expect(qwenTimestampedMaxChunk, const Duration(seconds: 180));
      expect(
        effectiveQwenChunk(const Duration(minutes: 20)),
        qwenTimestampedMaxChunk,
      );
      expect(effectiveQwenChunk(Duration.zero), qwenTimestampedMaxChunk);
      expect(
        effectiveQwenChunk(const Duration(milliseconds: 200)),
        const Duration(seconds: 1),
      );
    });
  });

  group('qwenMaxNewTokensFor', () {
    test('a song gets the budget of one 30 second chunk', () {
      // 128 + 30 * 8: enough for five CJK characters a second, far less than
      // a decoder stuck on one couplet would fill.
      for (final minutes in [3, 4, 7]) {
        expect(qwenMaxNewTokensFor(Duration(minutes: minutes)), 368);
      }
    });

    test('regression: a four-minute song no longer gets 2 176 tokens', () {
      // The old formula sized the budget for a 1200 s chunk, but timestamped
      // requests are cut at 180 s at most, so each chunk could decode several
      // times more than its lyrics: room for a loop to fill the song.
      final fourMinutes = qwenMaxNewTokensFor(const Duration(minutes: 4));
      expect(fourMinutes, lessThan(256 + 240 * 8));
      expect(
        qwenMaxNewTokensFor(
          const Duration(minutes: 4),
          chunk: qwenTimestampedMaxChunk,
        ),
        128 + 180 * 8,
      );
    });

    test('short audio is budgeted by its own length, with a floor', () {
      expect(qwenMaxNewTokensFor(Duration.zero), qwenDecodeMinimumTokens);
      expect(
        qwenMaxNewTokensFor(const Duration(seconds: 5)),
        qwenDecodeMinimumTokens,
      );
      expect(qwenMaxNewTokensFor(const Duration(seconds: 20)), 128 + 20 * 8);
    });

    test('grows with audio length up to one chunk, then stops', () {
      var previous = 0;
      for (final seconds in [0, 10, 20, 30, 60, 600]) {
        final budget = qwenMaxNewTokensFor(Duration(seconds: seconds));
        expect(budget, greaterThanOrEqualTo(previous));
        previous = budget;
      }
      expect(
        qwenMaxNewTokensFor(const Duration(seconds: 600)),
        qwenMaxNewTokensFor(qwenRecognitionChunk),
      );
    });

    test('is bounded by the longest chunk the runtime allows', () {
      expect(
        qwenMaxNewTokensFor(
          const Duration(days: 30),
          chunk: const Duration(hours: 1),
        ),
        qwenDecodeCeilingTokens,
      );
      expect(qwenDecodeCeilingTokens, 128 + 180 * 8);
    });

    test('is computed from the WAV bytes end to end', () {
      expect(
        qwenMaxNewTokensForPcmWav(_wavBytesForSeconds(240)),
        qwenMaxNewTokensFor(const Duration(minutes: 4)),
      );
      expect(
        qwenMaxNewTokensForPcmWav(
          _wavBytesForSeconds(240),
          chunk: qwenFallbackChunk,
        ),
        qwenMaxNewTokensFor(
          const Duration(minutes: 4),
          chunk: qwenFallbackChunk,
        ),
      );
    });
  });
}
