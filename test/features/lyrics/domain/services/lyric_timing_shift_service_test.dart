import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_timing_shift_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

Duration ms(int value) => Duration(milliseconds: value);

List<(int, int)> spans(LyricDocument document) => [
  for (final l in document.lines)
    (l.startTime.inMilliseconds, l.endTime.inMilliseconds),
];

void main() {
  const service = LyricTimingShiftService();
  final song = LyricDocument(
    language: 'zh',
    lines: [
      line('第一句', 0, 2000),
      line('第二句', 3000, 5000),
      line('第三句', 6000, 8000),
    ],
  );

  group('offset', () {
    test('moves only the rows in the range', () {
      final result = service.apply(
        song,
        LyricTimingShift.offset(firstIndex: 1, lastIndex: 2, delta: ms(1500)),
      );
      expect(result.isSuccess, isTrue);
      expect(spans(result.document!), [(0, 2000), (4500, 6500), (7500, 9500)]);
      expect(result.changedIndices, [1, 2]);
      expect(result.clampedCount, 0);
      expect(result.scale, 1);
      expect(result.introducedIssues, isEmpty);
      expect(result.document!.lines.map((l) => l.text), ['第一句', '第二句', '第三句']);
    });

    test('clamps at 0:00, keeps the length and reports new conflicts', () {
      final result = service.apply(
        song,
        LyricTimingShift.offset(firstIndex: 0, lastIndex: 2, delta: ms(-4000)),
      );
      expect(spans(result.document!), [(0, 2000), (0, 2000), (2000, 4000)]);
      // The first row ends up where it was, so only two rows changed.
      expect(result.changedIndices, [1, 2]);
      expect(result.clampedCount, 2);
      expect(result.introducedIssues, isNotEmpty);
    });

    test('clamps an end past the audio', () {
      final result = service.apply(
        song,
        LyricTimingShift.offset(firstIndex: 2, lastIndex: 2, delta: ms(3000)),
        audioDuration: ms(10000),
      );
      expect(spans(result.document!).last, (9000, 10000));
      expect(result.clampedCount, 1);
    });

    test('reports the conflicts it removes', () {
      final overlapping = LyricDocument(
        language: 'zh',
        lines: [line('第一句', 0, 3500), line('第二句', 3000, 5000)],
      );
      final result = service.apply(
        overlapping,
        LyricTimingShift.offset(firstIndex: 1, lastIndex: 1, delta: ms(600)),
      );
      expect(result.resolvedIssues, isNotEmpty);
      expect(result.introducedIssues, isEmpty);
    });
  });

  group('two-point calibration', () {
    final spaced = LyricDocument(
      language: 'zh',
      lines: [
        line('第一句', 10000, 12000),
        line('第二句', 20000, 22000),
        line('第三句', 30000, 32000),
      ],
    );

    test('maps every timestamp linearly through the anchors', () {
      final result = service.apply(
        spaced,
        LyricTimingShift.twoPoint(
          firstIndex: 0,
          lastIndex: 2,
          fromIndex: 0,
          fromTarget: ms(11000),
          toIndex: 2,
          toTarget: ms(33000),
        ),
      );
      expect(result.scale, closeTo(1.1, 1e-9));
      expect(spans(result.document!), [
        (11000, 13200),
        (22000, 24200),
        (33000, 35200),
      ]);
    });

    test('rejects coinciding anchors and implausible scales', () {
      LyricTimingShiftFailure? failure(LyricTimingShift shift) =>
          service.apply(spaced, shift).failure;

      expect(
        failure(
          LyricTimingShift.twoPoint(
            firstIndex: 0,
            lastIndex: 2,
            fromIndex: 1,
            fromTarget: ms(1000),
            toIndex: 1,
            toTarget: ms(2000),
          ),
        ),
        LyricTimingShiftFailure.anchorsCoincide,
      );
      expect(
        failure(
          LyricTimingShift.twoPoint(
            firstIndex: 0,
            lastIndex: 2,
            fromIndex: 0,
            fromTarget: ms(30000),
            toIndex: 2,
            toTarget: ms(10000),
          ),
        ),
        LyricTimingShiftFailure.implausibleScale,
      );
      expect(
        failure(
          LyricTimingShift.twoPoint(
            firstIndex: 0,
            lastIndex: 2,
            fromIndex: 0,
            fromTarget: ms(10000),
            toIndex: 2,
            toTarget: ms(60000),
          ),
        ),
        LyricTimingShiftFailure.implausibleScale,
      );
      expect(
        failure(
          LyricTimingShift.twoPoint(
            firstIndex: 0,
            lastIndex: 2,
            fromIndex: 0,
            fromTarget: ms(10000),
            toIndex: 5,
            toTarget: ms(20000),
          ),
        ),
        LyricTimingShiftFailure.invalidAnchor,
      );
    });
  });

  test('rejects an invalid range and a shift that changes nothing', () {
    expect(
      service
          .apply(
            song,
            LyricTimingShift.offset(firstIndex: 2, lastIndex: 1, delta: ms(1)),
          )
          .failure,
      LyricTimingShiftFailure.invalidRange,
    );
    expect(
      service
          .apply(
            song,
            LyricTimingShift.offset(firstIndex: 0, lastIndex: 9, delta: ms(1)),
          )
          .failure,
      LyricTimingShiftFailure.invalidRange,
    );
    expect(
      service
          .apply(
            song,
            const LyricTimingShift.offset(
              firstIndex: 0,
              lastIndex: 2,
              delta: Duration.zero,
            ),
          )
          .failure,
      LyricTimingShiftFailure.noChange,
    );
  });

  group('time input', () {
    test('parses minutes, seconds, hours and signs', () {
      expect(parseLyricTimeInput('1:23.45'), ms(83450));
      expect(parseLyricTimeInput('83.45'), ms(83450));
      expect(parseLyricTimeInput(' -0.5 '), ms(-500));
      expect(parseLyricTimeInput('+1.2s'), ms(1200));
      expect(parseLyricTimeInput('1:02:03.5'), ms(3723500));
      expect(parseLyricTimeInput('1：05'), ms(65000));
      expect(parseLyricTimeInput('2秒'), ms(2000));
    });

    test('rejects malformed input', () {
      for (final raw in ['', 'abc', '1:75', '1:2:3:4', '1:-5', '--1']) {
        expect(parseLyricTimeInput(raw), isNull, reason: raw);
      }
    });

    test('formats what it parses', () {
      expect(formatLyricTimeInput(ms(83450)), '1:23.45');
      expect(formatLyricTimeInput(ms(5)), '0:00.01');
      expect(formatLyricTimeInput(ms(-500)), '-0:00.50');
      expect(parseLyricTimeInput(formatLyricTimeInput(ms(201230))), ms(201230));
      expect(formatLyricOffset(ms(1250)), '+1.25 s');
      expect(formatLyricOffset(ms(-100)), '-0.10 s');
    });
  });
}
