import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_timeline_auto_repair_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricTimelineAutoRepairService();

  LyricLine line(String text, int startMs, int endMs, {String? id}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        id: id,
      );

  test('trims an overlapping end when a changed adjacent line provides a clear boundary', () {
    final result = service.repair(
      lines: [
        line('first', 1000, 5000, id: 'a'),
        line('inserted', 4000, 5000, id: 'b'),
        line('third', 5000, 8000, id: 'c'),
      ],
      changedLineIndices: {1},
    );

    expect(result.repairs, hasLength(1));
    expect(result.repairs.single.lineIndex, 0);
    expect(result.repairs.single.previousEndTime, const Duration(milliseconds: 5000));
    expect(result.repairs.single.repairedEndTime, const Duration(milliseconds: 4000));
    expect(result.lines[0].endTime, const Duration(milliseconds: 4000));
    expect(result.lines[1].startTime, const Duration(milliseconds: 4000));
  });

  test('does not change unrelated pre-existing overlaps', () {
    final input = [
      line('first', 1000, 5000, id: 'a'),
      line('second', 4000, 7000, id: 'b'),
    ];
    final result = service.repair(lines: input, changedLineIndices: {8});

    expect(result.repairs, isEmpty);
    expect(result.lines[0].endTime, const Duration(milliseconds: 5000));
  });

  test('does not trim a manually calibrated line', () {
    final result = service.repair(
      lines: [
        line('manual', 1000, 5000, id: 'a'),
        line('inserted', 4000, 5000, id: 'b'),
      ],
      changedLineIndices: {1},
      protectedLineIndices: {0},
    );

    expect(result.repairs, isEmpty);
    expect(result.lines[0].endTime, const Duration(milliseconds: 5000));
  });

  test('leaves duplicate starts unresolved instead of fabricating start times', () {
    final result = service.repair(
      lines: [
        line('first', 1000, 5000, id: 'a'),
        line('inserted', 1000, 6000, id: 'b'),
      ],
      changedLineIndices: {1},
    );

    expect(result.repairs, isEmpty);
    expect(result.lines[0].startTime, result.lines[1].startTime);
  });

  test('clips a changed line at the audio end when a valid duration remains', () {
    final result = service.repair(
      lines: [line('tail', 7000, 12000, id: 'a')],
      changedLineIndices: {0},
      audioDuration: const Duration(milliseconds: 10000),
    );

    expect(result.repairs, hasLength(1));
    expect(result.repairs.single.type, LyricTimelineAutoRepairType.trimAudioBoundary);
    expect(result.lines.single.endTime, const Duration(milliseconds: 10000));
  });

  test('does not create a zero-duration interval at the audio boundary', () {
    final result = service.repair(
      lines: [line('tail', 10000, 12000, id: 'a')],
      changedLineIndices: {0},
      audioDuration: const Duration(milliseconds: 10000),
    );

    expect(result.repairs, isEmpty);
    expect(result.lines.single.endTime, const Duration(milliseconds: 12000));
  });
}
