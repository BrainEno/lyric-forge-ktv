import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/whisper_loop_recovery.dart';

import 'whisper_loop_fixtures.dart';

List<LyricLine> _repeated(String text, int count, int startMs, int stepMs) => [
  for (var i = 0; i < count; i++)
    loopLine(text, startMs + i * stepMs, startMs + (i + 1) * stepMs),
];

void main() {
  const policy = WhisperLoopRecoveryPolicy();

  group('plan', () {
    test('covers the loop and its compressed lead-in up to the next row', () {
      final lines = whisperLoopedSong();
      final regions = policy.plan(lines);

      expect(regions, hasLength(1));
      final region = regions.single;
      expect(region.start, const Duration(milliseconds: 89280));
      expect(region.end, lines[32].startTime);
      expect(region.loopedRowCount, 22);
      expect(region.replacedIndicesIn(lines), {for (var i = 4; i < 32; i++) i});
    });

    test('leaves weak loops to the fusion step', () {
      final lines = [
        loopLine('verse line', 0, 3000),
        ..._repeated('let it go', 3, 3000, 3000),
        loopLine('next line', 12000, 15000),
      ];
      expect(policy.plan(lines), isEmpty);
    });

    test('merges nearby loops and stretches short regions', () {
      final lines = [
        ..._repeated('first loop line here', 6, 0, 500),
        loopLine('a real line between', 3000, 5000),
        ..._repeated('second loop line here', 6, 6000, 500),
      ];
      final regions = policy.plan(lines);
      expect(regions, hasLength(1));
      expect(regions.single.loops, hasLength(2));
      expect(regions.single.start, Duration.zero);
      // Both loops plus the row between them are decoded again.
      expect(regions.single.replacedIndicesIn(lines), {
        for (var i = 0; i < lines.length; i++) i,
      });
      expect(
        regions.single.duration,
        greaterThanOrEqualTo(WhisperLoopRecoveryPolicy.minRegion),
      );
    });

    test('never runs past the end of the audio', () {
      final lines = _repeated('the end the end my friend', 6, 0, 500);
      final region = policy
          .plan(lines, audioDuration: const Duration(seconds: 5))
          .single;
      expect(region.end, const Duration(seconds: 5));
    });

    test('caps the number of re-decodes, keeping the largest loops', () {
      final lines = <LyricLine>[];
      var start = 0;
      for (var loop = 0; loop < 5; loop++) {
        final count = 6 + loop;
        lines.addAll(
          _repeated('loop number $loop goes on', count, start, 1000),
        );
        start += count * 1000 + 30000;
        lines.add(loopLine('real line $loop', start - 25000, start - 20000));
      }
      final regions = policy.plan(lines);
      expect(regions, hasLength(WhisperLoopRecoveryPolicy.maxRegions));
      expect(regions.map((region) => region.loopedRowCount), [8, 9, 10]);
      // Still in timeline order.
      expect(
        regions.map((region) => region.start).toList(),
        orderedEquals(
          regions.map((region) => region.start).toList()
            ..sort((a, b) => a.compareTo(b)),
        ),
      );
    });
  });

  group('splice', () {
    test('replaces the looped rows with a loop-free re-decode', () {
      final lines = whisperLoopedSong();
      final region = policy.plan(lines).single;
      final redecoded = [
        // Before the region: ignored.
        loopLine('Tell me again why the road never ends', 85000, 89000),
        loopLine(
          'How far is the harbour, is it under the water?',
          89500,
          95000,
        ),
        loopLine('I hope we arrive in time', 95500, 99000),
        loopLine('Now you never look back on the way', 101500, 107000),
        loopLine('Oh, and the lanterns that you hold', 107500, 113500),
        // Runs past the region: clipped.
        loopLine('Oh, but the people you know', 114000, 119000),
        // After the region: ignored.
        loopLine('What they say', 118000, 121000),
      ];

      final splice = policy.splice(
        lines: lines,
        region: region,
        redecoded: redecoded,
      );

      expect(splice.outcome, WhisperLoopRegionOutcome.replaced);
      expect(splice.insertedCount, 5);
      expect(splice.lines.map((line) => line.text), [
        'Wake me up when the city is quiet',
        'Carry me home on a paper balloon',
        'Now the river is wide and the morning is near',
        'Tell me again why the road never ends',
        'How far is the harbour, is it under the water?',
        'I hope we arrive in time',
        'Now you never look back on the way',
        'Oh, and the lanterns that you hold',
        'Oh, but the people you know',
        'What they say, oh, the truth is we never care',
        'And that is quite enough of that',
      ]);
      expect(splice.lines[8].endTime, region.end);
      for (var i = 1; i < splice.lines.length; i++) {
        expect(
          splice.lines[i].startTime >= splice.lines[i - 1].startTime,
          isTrue,
        );
      }
    });

    test('keeps the first pass when the re-decode loops as well', () {
      final lines = whisperLoopedSong();
      final region = policy.plan(lines).single;
      final splice = policy.splice(
        lines: lines,
        region: region,
        redecoded: _repeated(
          'Oh, and the lanterns that you hold',
          8,
          90000,
          3000,
        ),
      );
      expect(splice.outcome, WhisperLoopRegionOutcome.stillLooping);
      expect(identical(splice.lines, lines), isTrue);
    });

    test('keeps the first pass when nothing lands inside the region', () {
      final lines = whisperLoopedSong();
      final region = policy.plan(lines).single;
      final splice = policy.splice(
        lines: lines,
        region: region,
        redecoded: [loopLine('somewhere else', 0, 2000)],
      );
      expect(splice.outcome, WhisperLoopRegionOutcome.empty);
      expect(identical(splice.lines, lines), isTrue);
    });
  });
}
