import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_auditor.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_word_timing_editor.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration ms(int value) => Duration(milliseconds: value);

LyricWordTiming w(String text, int start, int end) =>
    LyricWordTiming(text: text, start: ms(start), end: ms(end));

LyricLine row(
  String text,
  int start,
  int end, {
  List<LyricWordTiming> words = const [],
  String? id,
}) => LyricLine(
  text: text,
  startTime: ms(start),
  endTime: ms(end),
  words: words,
  id: id,
);

List<(String, int, int)> times(List<LyricWordTiming> words) => [
  for (final word in words)
    (word.text, word.start.inMilliseconds, word.end.inMilliseconds),
];

void main() {
  group('word timing check', () {
    const auditor = LyricWordTimingAuditor();

    test('finds stale, drifted, long, squeezed and gapped rows', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [
          // 0: fine.
          row('我爱你', 0, 900, words: [w('我', 0, 300), w('爱', 300, 600), w('你', 600, 900)]),
          // 1: a character was added after recognition.
          row('我爱你们', 1000, 2000, words: [w('我', 1000, 1300), w('爱', 1300, 1600), w('你', 1600, 2000)]),
          // 2: the row was moved by two seconds.
          row('你好', 5000, 6000, words: [w('你', 3000, 3500), w('好', 3500, 4000)]),
          // 3: a word held three seconds, then a squeezed one.
          row('啊呀', 7000, 10100, words: [w('啊', 7000, 10000), w('呀', 10000, 10020)]),
          // 4: a long breath inside the row.
          row('一二', 11000, 14000, words: [w('一', 11000, 11500), w('二', 13000, 14000)]),
          // 5: no word timing at all.
          row('没有', 15000, 16000),
          row('', 16000, 17000),
        ],
      );
      final plan = auditor.plan(document);
      expect(plan.sungRows, 6);
      expect(plan.timedRows, 4);
      expect(
        [for (final issue in plan.issues) (issue.kind, issue.index)],
        [
          (LyricWordTimingIssueKind.stale, 1),
          (LyricWordTimingIssueKind.drifted, 2),
          (LyricWordTimingIssueKind.longWord, 3),
          (LyricWordTimingIssueKind.shortWords, 3),
          (LyricWordTimingIssueKind.innerGap, 4),
        ],
      );
      expect(plan.issues[2].word, '啊');
      expect(plan.issues[2].duration, ms(3000));
      expect(plan.issues[3].count, 1);
      expect(plan.issues[4].word, '二');
      expect(plan.issues[4].duration, ms(1500));
      expect(plan.issues[1].recordedStart, ms(3000));
      expect(plan.fixablePositions, [0, 1]);

      final fixed = plan.applyTo(document, plan.fixablePositions.toSet());
      expect(fixed.lines[1].words, isEmpty);
      expect(fixed.lines[1].text, '我爱你们');
      expect(times(fixed.lines[2].words), [('你', 5000, 5500), ('好', 5500, 6000)]);
      expect(fixed.lines[2].startTime, ms(5000));
      expect(auditor.plan(fixed).fixablePositions, isEmpty);
      expect(identical(plan.applyTo(document, {}), document), isTrue);
    });

    test('draft health counts stale word timing', () {
      final health = const LyricDraftHealthService().analyze(
        LyricDocument(
          language: 'zh',
          lines: [
            row('我爱你们', 0, 1000, words: [w('我', 0, 500), w('爱', 500, 1000)]),
          ],
        ),
      );
      expect(health.staleWordRows, 1);
      expect(health.hasIssues, isTrue);
    });
  });

  group('word timing editor', () {
    const editor = LyricWordTimingEditor();
    final words = [w('我', 1000, 1300), w('爱', 1300, 1600), w('你', 1800, 2000)];

    test('moving a shared boundary moves both words', () {
      final later = editor.moveStart(words, 1, ms(1400));
      expect(times(later).take(2), [('我', 1000, 1400), ('爱', 1400, 1600)]);
      final earlier = editor.moveEnd(words, 0, ms(1200));
      expect(times(earlier).take(2), [('我', 1000, 1200), ('爱', 1200, 1600)]);
    });

    test('a gap stays until a word is pushed into its neighbour', () {
      expect(times(editor.moveEnd(words, 1, ms(1700)))[2], ('你', 1800, 2000));
      final pushed = editor.moveEnd(words, 1, ms(1900));
      expect(times(pushed).sublist(1), [('爱', 1300, 1900), ('你', 1900, 2000)]);
    });

    test('words never go shorter than the minimum or past their bounds', () {
      expect(times(editor.moveStart(words, 0, ms(1290)))[0], ('我', 1260, 1300));
      expect(times(editor.moveEnd(words, 2, ms(1500)))[2], ('你', 1800, 1840));
      expect(
        times(editor.moveEnd(words, 2, ms(9000), ceiling: ms(2500)))[2],
        ('你', 1800, 2500),
      );
      expect(times(editor.moveStart(words, 1, ms(0)))[1], ('爱', 1040, 1600));
      expect(times(editor.moveStart(words, 0, ms(-500)))[0], ('我', 0, 1300));
    });

    test('shifting keeps the length', () {
      final moved = editor.shift(words, 2, ms(-100));
      expect(times(moved).sublist(1), [('爱', 1300, 1600), ('你', 1700, 1900)]);
      final blocked = editor.shift(words, 2, ms(500), ceiling: ms(2100));
      expect(times(blocked)[2], ('你', 1900, 2100));
    });

    test('merge and split', () {
      final merged = editor.mergeWithNext(words, 0);
      expect(times(merged).first, ('我爱', 1000, 1600));
      expect(
        times(editor.mergeWithNext([w('Hold', 0, 400), w('me', 400, 800)], 0)),
        [('Hold me', 0, 800)],
      );
      final split = editor.split(merged, 0);
      expect(times(split).take(2), [('我', 1000, 1300), ('爱', 1300, 1600)]);
      expect(identical(editor.split(words, 0), words), isTrue);
      expect(
        times(editor.split([w('你好吗？', 0, 900)], 0)),
        [('你好', 0, 600), ('吗？', 600, 900)],
      );
    });

    test('starts from the row or the estimate and applies to the row', () {
      final line = row('我爱你', 1000, 2000, words: words, id: 'a');
      final own = editor.start(line);
      expect(own.estimated, isFalse);
      expect(times(own.words), times(words));

      final plain = editor.start(row('你好', 0, 1000));
      expect(plain.estimated, isTrue);
      expect(times(plain.words), [('你', 0, 500), ('好', 500, 1000)]);

      final grown = editor.apply(line, editor.moveStart(words, 0, ms(900)));
      expect(grown.startTime, ms(900));
      expect(grown.endTime, ms(2000));
      final fitted = editor.apply(line, words, fitRow: true);
      expect(fitted.endTime, ms(2000));
      expect(editor.apply(line, words.sublist(0, 2), fitRow: true).endTime, ms(1600));

      final document = editor.replaceRow(
        LyricDocument(language: 'zh', lines: [line]),
        0,
        fitted,
      );
      expect(
        (document.metadata[kLyricTimingProvenanceKey] as Map)['a'],
        LyricTimingProvenance.manual.name,
      );
    });
  });
}
