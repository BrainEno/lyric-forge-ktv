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

  group('qwenMaxNewTokensFor', () {
    test('never goes below the fixed budget it replaced', () {
      // Short clips used to be capped at 1024 as well, so raising the budget
      // must not lower anything.
      expect(qwenMaxNewTokensFor(Duration.zero), qwenDecodeMinimumTokens);
      expect(
        qwenMaxNewTokensFor(const Duration(seconds: 30)),
        qwenDecodeMinimumTokens,
      );
    });

    test('a normal song gets a larger budget than the old constant', () {
      final fourMinutes = qwenMaxNewTokensFor(const Duration(minutes: 4));

      expect(fourMinutes, greaterThan(1024));
      expect(fourMinutes, 256 + 240 * 8);
    });

    test('grows monotonically with audio length', () {
      var previous = 0;
      for (final seconds in [0, 60, 120, 180, 240, 300, 600, 1200]) {
        final budget = qwenMaxNewTokensFor(Duration(seconds: seconds));
        expect(
          budget,
          greaterThanOrEqualTo(previous),
          reason: '$seconds s must not shrink the budget',
        );
        previous = budget;
      }
    });

    test('stops growing at the runtime chunk limit', () {
      // The runtime never hands the decoder more than one 1200 s chunk, so a
      // longer file must not inflate the per-request budget.
      final atLimit = qwenMaxNewTokensFor(qwenRuntimeMaxChunk);
      expect(qwenMaxNewTokensFor(const Duration(minutes: 40)), atLimit);
      expect(atLimit, 256 + 1200 * 8);
      expect(atLimit, lessThan(qwenDecodeMaximumTokens));
    });

    test('is bounded even for an absurd duration', () {
      expect(
        qwenMaxNewTokensFor(const Duration(days: 30)),
        qwenDecodeMaximumTokens,
      );
    });

    test('is computed from the WAV bytes end to end', () {
      expect(
        qwenMaxNewTokensForPcmWav(_wavBytesForSeconds(240)),
        qwenMaxNewTokensFor(const Duration(minutes: 4)),
      );
    });
  });
}
