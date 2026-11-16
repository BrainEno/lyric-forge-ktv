import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_text_cleanup_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Synthetic lines written for these tests, not taken from a song.
LyricDocument _doc(List<String> texts, {Map<String, dynamic>? metadata}) =>
    LyricDocument(
      language: 'zh',
      lines: [
        for (final (index, text) in texts.indexed)
          LyricLine(
            id: 'l$index',
            text: text,
            startTime: Duration(seconds: index * 4),
            endTime: Duration(seconds: index * 4 + 3),
            confidence: 70 + index,
          ),
      ],
      metadata: metadata ?? const {},
    );

void main() {
  const service = LyricTextCleanupService();
  const defaults = LyricTextCleanupRule.defaults;

  group('text rules', () {
    test('removes trailing sentence punctuation but keeps ? and !', () {
      expect(service.cleanText('我爱你。', defaults), '我爱你');
      expect(service.cleanText('我爱你，', defaults), '我爱你');
      expect(service.cleanText('Hold me tight.', defaults), 'Hold me tight');
      expect(service.cleanText('你在哪里？', defaults), '你在哪里？');
      expect(service.cleanText('Oh yeah!', defaults), 'Oh yeah!');
    });

    test('turns punctuation inside a CJK line into one space', () {
      expect(service.cleanText('我爱你，你爱我。', defaults), '我爱你 你爱我');
      expect(service.cleanText('我爱你 ， 你爱我', defaults), '我爱你 你爱我');
      expect(service.cleanText('我爱你,你爱我', defaults), '我爱你 你爱我');
    });

    test('keeps ASCII commas between Latin words and decimal points', () {
      expect(
        service.cleanText('I love you, baby', defaults),
        'I love you, baby',
      );
      expect(service.cleanText('调频 98.6 兆赫', defaults), '调频 98.6 兆赫');
    });

    test('converts full-width ASCII letters and digits', () {
      expect(service.cleanText('ＬＯＶＥ１２３', defaults), 'LOVE123');
      // Full-width CJK punctuation keeps its meaning.
      expect(
        service.cleanText('你好吗？', {LyricTextCleanupRule.fullWidthAscii}),
        '你好吗？',
      );
    });

    test('strips known annotations but keeps sung parentheticals', () {
      expect(service.cleanText('[音乐] 我爱你', defaults), '我爱你');
      expect(service.cleanText('我爱你 (Music)', defaults), '我爱你');
      expect(service.cleanText('♪ 我爱你 ♪', defaults), '我爱你');
      expect(service.cleanText('我爱你（你在哪里）', defaults), '我爱你（你在哪里）');
    });

    test('removes spaces between Han characters only when asked', () {
      const text = '我 爱 你';
      expect(service.cleanText(text, defaults), text);
      expect(
        service.cleanText(text, {LyricTextCleanupRule.removeCjkSpaces}),
        '我爱你',
      );
      // Korean separates words with spaces; never joined.
      expect(
        service.cleanText('사랑 해', {LyricTextCleanupRule.removeCjkSpaces}),
        '사랑 해',
      );
      // Between Han and Latin a space stays.
      expect(
        service.cleanText('我爱 you', {LyricTextCleanupRule.removeCjkSpaces}),
        '我爱 you',
      );
    });

    test('collapses whitespace and ideographic spaces', () {
      expect(service.cleanText('  我爱你\u3000\u3000你爱我  ', defaults), '我爱你 你爱我');
    });

    test('reports the rules that changed the text', () {
      final applied = <LyricTextCleanupRule>[];
      service.cleanText('[音乐]我爱你。', defaults, appliedRules: applied);
      expect(applied, [
        LyricTextCleanupRule.stripAnnotations,
        LyricTextCleanupRule.trailingPunctuation,
      ]);
    });

    test('a disabled whitespace rule keeps original padding', () {
      expect(
        service.cleanText('  我爱你。', {LyricTextCleanupRule.trailingPunctuation}),
        '  我爱你',
      );
    });
  });

  group('row detection', () {
    test('recognises recogniser caption hallucinations', () {
      expect(service.isAsrBoilerplate('字幕由Amara.org社区提供'), isTrue);
      expect(service.isAsrBoilerplate('請不吝點讚 訂閱 轉發 打賞支持明鏡與點點欄目'), isTrue);
      expect(service.isAsrBoilerplate('谢谢观看！'), isTrue);
      expect(service.isAsrBoilerplate('Thanks for watching!'), isTrue);
      // A long sung line that merely contains the phrase is kept.
      expect(service.isAsrBoilerplate('谢谢观看这场雨中的我们最后的告别演出'), isFalse);
      expect(service.isAsrBoilerplate('我爱你'), isFalse);
    });

    test('recognises annotation-only rows', () {
      expect(service.isAnnotationOnly('[音乐]'), isTrue);
      expect(service.isAnnotationOnly('♪♪♪'), isTrue);
      expect(service.isAnnotationOnly('(Music) ...'), isTrue);
      expect(service.isAnnotationOnly('[音乐] 我爱你'), isFalse);
      expect(service.isAnnotationOnly('。。。'), isFalse);
    });
  });

  group('plan', () {
    test('lists rewrites and removals without touching timing', () {
      final document = _doc([
        '我爱你，你爱我。',
        '[音乐]',
        '蜜雪冰城甜蜜蜜',
        '字幕由Amara.org社区提供',
        '',
      ]);
      final plan = service.plan(document);

      expect(plan.changes.map((change) => change.index), [0]);
      expect(plan.changes.single.after, '我爱你 你爱我');
      expect(plan.removals.map((removal) => removal.index), [1, 3]);
      expect(plan.removals.map((removal) => removal.rule), [
        LyricTextCleanupRule.removeAnnotationOnlyLines,
        LyricTextCleanupRule.removeAsrBoilerplate,
      ]);
      // Empty rows stay unless the rule is switched on.
      expect(plan.removals.any((removal) => removal.index == 4), isFalse);

      final applied = plan.applyTo(document);
      expect(applied.lines.map((line) => line.text), [
        '我爱你 你爱我',
        '蜜雪冰城甜蜜蜜',
        '',
      ]);
      expect(applied.lines.first.startTime, document.lines.first.startTime);
      expect(applied.lines.first.id, 'l0');
      expect(applied.lines.first.confidence, document.lines.first.confidence);
      expect(applied.lines[1].id, 'l2');
    });

    test('removes empty rows when enabled', () {
      final plan = service.plan(
        _doc(['我爱你', '  ', '你爱我']),
        rules: {LyricTextCleanupRule.removeEmptyLines},
      );
      expect(plan.removals.single.index, 1);
    });

    test('a row that a text rule would empty is never blanked', () {
      final plan = service.plan(
        _doc(['[音乐]', '我爱你']),
        rules: {LyricTextCleanupRule.stripAnnotations},
      );
      expect(plan.hasChanges, isFalse);
    });

    test('skips manually edited rows unless opted in', () {
      final document = _doc(['我爱你。', '[音乐]', '你爱我。']);
      final plan = service.plan(document, protectedIndices: {0, 1});
      expect(plan.changes.map((change) => change.index), [2]);
      expect(plan.removals, isEmpty);
      expect(plan.skippedProtectedIndices, [0, 1]);
    });

    test('counts rows per rule', () {
      final plan = service.plan(_doc(['我爱你。', '你爱我，', '[音乐]', 'ＯＫ']));
      expect(plan.countsByRule[LyricTextCleanupRule.trailingPunctuation], 2);
      expect(
        plan.countsByRule[LyricTextCleanupRule.removeAnnotationOnlyLines],
        1,
      );
      expect(plan.countsByRule[LyricTextCleanupRule.fullWidthAscii], 1);
    });

    test('shifts row-indexed review evidence past removed rows', () {
      final document = _doc(
        ['[音乐]', '我爱你', '你爱我'],
        metadata: {
          LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [0, 2],
          LyricIndexedReviewMetadata.secondaryOnlyCountKey: 2,
        },
      );
      final applied = service.plan(document).applyTo(document);
      expect(
        applied.metadata[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey],
        [1],
      );
    });

    test('refuses to apply over a row that changed meanwhile', () {
      final document = _doc(['我爱你。']);
      final plan = service.plan(document);
      final edited = document.copyWith(
        lines: [document.lines.first.copyWith(text: '我恨你。')],
      );
      expect(() => plan.applyTo(edited), throwsStateError);
    });

    test('selection after apply accounts for removed rows', () {
      final document = _doc(['[音乐]', '[音乐]', '我爱你。']);
      final plan = service.plan(document);
      expect(plan.selectionAfterApply(document.lines.length), 0);

      final onlyRemovals = service.plan(_doc(['我爱你', '[音乐]']));
      expect(onlyRemovals.selectionAfterApply(2), 0);
    });
  });
}
