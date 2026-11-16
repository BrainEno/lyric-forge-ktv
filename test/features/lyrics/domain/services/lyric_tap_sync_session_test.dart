import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_tap_sync_session.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

Duration ms(int value) => Duration(milliseconds: value);

List<(int, int)> spans(LyricDocument document) => [
  for (final l in document.lines)
    (l.startTime.inMilliseconds, l.endTime.inMilliseconds),
];

List<(int, int, int?)> marks(LyricTapSyncSession session) => [
  for (final mark in session.marks)
    (mark.lineIndex, mark.start.inMilliseconds, mark.end?.inMilliseconds),
];

void main() {
  final song = LyricDocument(
    language: 'zh',
    lines: [
      line('第一行', 0, 10500, id: 'l0'),
      line('第二行', 9000, 11000, id: 'l1'),
      line('第三行', 11500, 13000, id: 'l2'),
      line('第四行', 14000, 16000, id: 'l3'),
    ],
  );

  group('LyricTapSyncSession presses', () {
    test('each press times the next row and bounces are ignored', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 1);
      expect(session.cursor, 1);
      expect(session.press(ms(10000)), isTrue);
      expect(session.press(ms(10050)), isFalse);
      expect(session.press(ms(12000)), isTrue);
      expect(session.cursor, 3);
      expect(session.openIndex, 2);
      expect(marks(session), [(1, 10000, null), (2, 12000, null)]);
    });

    test('release ends the open row, never shorter than the minimum', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 0)
        ..press(ms(10000));
      expect(session.release(ms(10050)), isTrue);
      expect(marks(session), [(0, 10000, 10100)]);
      expect(session.openIndex, isNull);
      expect(session.release(ms(11000)), isFalse);
    });

    test('pressing before the previous release cuts the previous row', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 0)
        ..press(ms(10000))
        ..release(ms(12000))
        ..press(ms(11500));
      expect(marks(session), [(0, 10000, 11500), (1, 11500, null)]);
    });

    test('a press earlier than the last row rewinds and re-times', () {
      final session = LyricTapSyncSession(lineCount: 5, startIndex: 1)
        ..press(ms(10000))
        ..press(ms(12000))
        ..press(ms(14000));
      expect(session.press(ms(11000)), isTrue);
      expect(marks(session), [(1, 10000, null), (2, 11000, null)]);
    });

    test('rewindTo re-opens a row whose end is after the moment', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 0)
        ..press(ms(1000))
        ..release(ms(3000))
        ..press(ms(4000));
      expect(session.rewindTo(ms(2000)), 1);
      expect(marks(session), [(0, 1000, null)]);
    });

    test('undo takes back an explicit end first, then the press', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 0)
        ..press(ms(1000))
        ..release(ms(2000));
      expect(session.undo(), ms(1000));
      expect(marks(session), [(0, 1000, null)]);
      expect(session.undo(), ms(1000));
      expect(session.isEmpty, isTrue);
      expect(session.undo(), isNull);
    });

    test('no presses are taken once every row is timed', () {
      final session = LyricTapSyncSession(lineCount: 2, startIndex: 1);
      expect(session.press(ms(1000)), isTrue);
      expect(session.isComplete, isTrue);
      expect(session.press(ms(3000)), isFalse);
    });
  });

  group('LyricTapSyncSession.apply', () {
    test('rows run to the next tap, explicit ends win, the row above is '
        'trimmed and timed rows become manual', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 1)
        ..press(ms(10000))
        ..press(ms(12000))
        ..release(ms(12800));
      final result = session.apply(song);
      expect(spans(result.document), [
        (0, 10000),
        (10000, 12000),
        (12000, 12800),
        (14000, 16000),
      ]);
      expect(result.timedIndices, [1, 2]);
      expect(result.trimmedPrevious, isTrue);
      expect(result.shiftedFollowingCount, 0);
      final provenance =
          result.document.metadata[kLyricTimingProvenanceKey] as Map;
      expect(provenance['l1'], LyricTimingProvenance.manual.name);
      expect(provenance['l2'], LyricTimingProvenance.manual.name);
      expect(provenance.containsKey('l0'), isFalse);
      // The text never changes.
      expect(
        result.document.lines.map((l) => l.text),
        song.lines.map((l) => l.text),
      );
    });

    test('shiftFollowing moves the untimed rows by the last drift', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 1)
        ..press(ms(10000))
        ..press(ms(12000))
        ..release(ms(12800));
      final result = session.apply(song, shiftFollowing: true);
      expect(spans(result.document).last, (14500, 16500));
      expect(result.shiftedFollowingCount, 1);
    });

    test('an open last row keeps its old length across an interlude', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [line('甲乙丙', 1000, 2000), line('丁', 30000, 31000)],
      );
      final session = LyricTapSyncSession(lineCount: 2, startIndex: 0)
        ..press(ms(5000));
      expect(spans(session.apply(document).document), [
        (5000, 6000),
        (30000, 31000),
      ]);
    });

    test('an open last row runs to a close next row', () {
      final session = LyricTapSyncSession(lineCount: 4, startIndex: 2)
        ..press(ms(11000));
      expect(spans(session.apply(song).document)[2], (11000, 14000));
    });

    test('an empty session changes nothing', () {
      final result = LyricTapSyncSession(
        lineCount: 4,
        startIndex: 0,
      ).apply(song);
      expect(result.changed, isFalse);
      expect(identical(result.document, song), isTrue);
    });
  });
}
