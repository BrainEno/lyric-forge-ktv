import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_tap_session.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration ms(int value) => Duration(milliseconds: value);

LyricLine row(String text, int startMs, int endMs, String id) =>
    LyricLine(text: text, startTime: ms(startMs), endTime: ms(endMs), id: id);

LyricDocument song() => LyricDocument(
  language: 'zh',
  lines: [
    row('前奏', 0, 1000, 'p'),
    row('我爱你，', 2000, 4000, 'a'),
    row('♪', 4000, 5000, 'm'),
    row('Hold me', 6000, 8000, 'b'),
    row('结束', 9000, 10000, 'c'),
  ],
);

List<(String, int, int)> words(LyricLine line) => [
  for (final word in line.words)
    (word.text, word.start.inMilliseconds, word.end.inMilliseconds),
];

void main() {
  LyricWordTapSession session({int start = 1}) =>
      LyricWordTapSession(lines: song().lines, startIndex: start);

  test('units follow karaoke units and rows without singing are skipped', () {
    final s = session();
    expect(s.rows.map((r) => r.lineIndex), [1, 3, 4]);
    expect(s.rows.first.units, ['我', '爱', '你，']);
    expect(s.rows[1].units, ['Hold ', 'me']);
    expect(s.unitCount, 7);
    expect(s.cursorRow, 0);
    expect(s.cursorUnit, 0);
  });

  test('presses advance unit by unit and across rows', () {
    final s = session();
    for (final t in [2100, 2400, 2700]) {
      expect(s.press(ms(t)), isTrue);
    }
    expect(s.cursorRow, 1);
    expect(s.cursorUnit, 0);
    expect(s.timedUnitsIn(0), 3);
    expect(s.completedRowCount, 1);
    // A bounce is ignored.
    expect(s.press(ms(2730)), isFalse);
    expect(s.press(ms(6000)), isTrue);
    expect(s.cursorUnit, 1);
  });

  test('apply writes word timing and row times for complete rows only', () {
    final s = session()
      ..press(ms(2100))
      ..press(ms(2400))
      ..press(ms(2700))
      ..press(ms(3500));
    final result = s.apply(song());
    expect(result.timedIndices, [1]);
    expect(result.partialIndex, 3);
    final line = result.document.lines[1];
    // The last unit runs into the next row's first press (800 ms later).
    expect(words(line), [
      ('我', 2100, 2400),
      ('爱', 2400, 2700),
      ('你，', 2700, 3500),
    ]);
    expect(line.startTime, ms(2100));
    expect(line.endTime, ms(3500));
    expect(const LyricWordTimingService().isUsable(line), isTrue);
    expect(result.document.lines[3].words, isEmpty);
    expect(
      (result.document.metadata[kLyricTimingProvenanceKey] as Map)['a'],
      LyricTimingProvenance.manual.name,
    );
  });

  test('a long pause before the next row ends the tail at the average', () {
    final s = session()
      ..press(ms(2000))
      ..press(ms(2400))
      ..press(ms(2800))
      ..press(ms(6000))
      ..press(ms(6500));
    final result = s.apply(song());
    expect(result.timedIndices, [1, 3]);
    // Average unit 400 ms: the tail ends at 3200 instead of running to 6000.
    expect(words(result.document.lines[1]).last, ('你，', 2800, 3200));
    // "me" is the last unit before an untimed row; one gap of 500 ms.
    expect(words(result.document.lines[3]), [
      ('Hold ', 6000, 6500),
      ('me', 6500, 7000),
    ]);
  });

  test('hold mode ends units at the release', () {
    final s = session(start: 4)
      ..press(ms(9000))
      ..release(ms(9300))
      ..press(ms(9500))
      ..release(ms(9520));
    final result = s.apply(song());
    expect(words(result.document.lines[4]), [
      ('结', 9000, 9300),
      ('束', 9500, 9560),
    ]);
    expect(result.document.lines[4].endTime, ms(9560));
  });

  test('undo, rewind and row start', () {
    final s = session()
      ..press(ms(2100))
      ..press(ms(2400))
      ..release(ms(2600));
    expect(s.undo(), ms(2400));
    expect(s.hasOpenUnit, isTrue);
    expect(s.undo(), ms(2400));
    expect(s.marks, hasLength(1));
    s
      ..press(ms(2400))
      ..press(ms(2700));
    expect(s.rowStart(0), ms(2100));
    // Pressing earlier than the last unit re-times from there.
    expect(s.press(ms(2300)), isTrue);
    expect(s.marks.map((m) => m.start), [ms(2100), ms(2300)]);
    expect(s.rewindTo(ms(2000)), 2);
    expect(s.isEmpty, isTrue);
  });

  test('the row before the session is trimmed when it overlaps', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [row('前面', 0, 3000, 'x'), row('后面', 3000, 5000, 'y')],
    );
    final s = LyricWordTapSession(lines: document.lines, startIndex: 1)
      ..press(ms(2500))
      ..press(ms(2900));
    final result = s.apply(document);
    expect(result.trimmedPrevious, isTrue);
    expect(result.document.lines.first.endTime, ms(2500));
  });

  test('nothing to time when only silent rows follow', () {
    final s = LyricWordTapSession(
      lines: [row('♪', 0, 1000, 'm'), row('', 1000, 2000, 'e')],
      startIndex: 0,
    );
    expect(s.rows, isEmpty);
    expect(s.isComplete, isTrue);
    expect(s.press(ms(100)), isFalse);
  });
}
