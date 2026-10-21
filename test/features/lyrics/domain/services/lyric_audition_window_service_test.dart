import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_audition_window_service.dart';

void main() {
  const service = LyricAuditionWindowService();

  test('uses a one-second pre-roll and stops at the line end', () {
    final window = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(milliseconds: 6200),
      audioDuration: const Duration(seconds: 30),
    );

    expect(window.canAudition, isTrue);
    expect(window.startAt, const Duration(seconds: 4));
    expect(window.endAt, const Duration(milliseconds: 6200));
    expect(window.hasKnownEnd, isTrue);
  });

  test('applies the global offset to both start and end before pre-roll', () {
    final window = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(milliseconds: 6200),
      globalOffset: const Duration(milliseconds: 600),
      audioDuration: const Duration(seconds: 30),
    );

    expect(window.startAt, const Duration(milliseconds: 4600));
    expect(window.endAt, const Duration(milliseconds: 6800));
  });

  test('clamps first-line pre-roll at zero', () {
    final window = service.calculate(
      lineStart: const Duration(milliseconds: 250),
      lineEnd: const Duration(milliseconds: 900),
      audioDuration: const Duration(seconds: 20),
    );

    expect(window.startAt, Duration.zero);
    expect(window.endAt, const Duration(milliseconds: 900));
  });

  test('clamps a final line end to the audio duration', () {
    final window = service.calculate(
      lineStart: const Duration(seconds: 8),
      lineEnd: const Duration(seconds: 12),
      audioDuration: const Duration(seconds: 10),
    );

    expect(window.startAt, const Duration(seconds: 7));
    expect(window.endAt, const Duration(seconds: 10));
    expect(window.canAudition, isTrue);
  });

  test('does not invent an auto-stop boundary when end time is unknown', () {
    final window = service.calculate(
      lineStart: const Duration(seconds: 4),
      lineEnd: null,
      audioDuration: const Duration(seconds: 10),
    );

    expect(window.startAt, const Duration(seconds: 3));
    expect(window.endAt, isNull);
    expect(window.hasKnownEnd, isFalse);
    expect(window.canAudition, isTrue);
  });

  test('rejects a line whose effective start is outside the audio', () {
    final window = service.calculate(
      lineStart: const Duration(seconds: 11),
      lineEnd: const Duration(seconds: 12),
      audioDuration: const Duration(seconds: 10),
    );

    expect(window.canAudition, isFalse);
    expect(window.startAt, const Duration(seconds: 10));
    expect(window.endAt, const Duration(seconds: 10));
  });

  test('rejects a present but non-positive lyric interval', () {
    final zeroLength = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(seconds: 5),
    );
    final reversed = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(seconds: 4),
    );

    expect(zeroLength.canAudition, isFalse);
    expect(reversed.canAudition, isFalse);
    expect(zeroLength.endAt, isNull);
    expect(reversed.endAt, isNull);
  });

  test('rejects a line whose end shifts entirely before audio time zero', () {
    final window = service.calculate(
      lineStart: const Duration(milliseconds: 200),
      lineEnd: const Duration(milliseconds: 500),
      globalOffset: const Duration(milliseconds: -800),
    );

    expect(window.canAudition, isFalse);
    expect(window.endAt, isNull);
  });

  test('uses configurable pre-roll and never accepts a negative pre-roll', () {
    final custom = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(seconds: 7),
      preRoll: const Duration(milliseconds: 350),
    );
    final negative = service.calculate(
      lineStart: const Duration(seconds: 5),
      lineEnd: const Duration(seconds: 7),
      preRoll: const Duration(seconds: -2),
    );

    expect(custom.startAt, const Duration(milliseconds: 4650));
    expect(negative.startAt, const Duration(seconds: 5));
  });
}
