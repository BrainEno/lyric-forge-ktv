import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_find_replace_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Synthetic lines written for these tests, not taken from a song.
LyricDocument _doc(List<String> texts) => LyricDocument(
  language: 'zh',
  lines: [
    for (final (index, text) in texts.indexed)
      LyricLine(
        id: 'l$index',
        text: text,
        startTime: Duration(seconds: index * 4),
        endTime: Duration(seconds: index * 4 + 3),
      ),
  ],
);

void main() {
  const service = LyricFindReplaceService();

  LyricFindReplacePlan plan(
    List<String> texts,
    String find,
    String replacement, {
    bool ignoreScript = true,
    bool ignoreCase = true,
    bool wholeWord = false,
    Set<int> protectedIndices = const {},
    bool includeProtected = false,
  }) => service.plan(
    _doc(texts),
    query: LyricFindReplaceQuery(
      find: find,
      replacement: replacement,
      ignoreChineseScript: ignoreScript,
      ignoreCase: ignoreCase,
      wholeWord: wholeWord,
    ),
    protectedIndices: protectedIndices,
    includeProtected: includeProtected,
  );

  test('replaces every occurrence on every row', () {
    final result = plan(['我碍你 我碍你', '你碍我', '我碍你到永远'], '碍', '爱');
    expect(result.matches.map((match) => match.index), [0, 1, 2]);
    expect(result.totalOccurrences, 4);
    expect(result.changes.map((match) => match.after), [
      '我爱你 我爱你',
      '你爱我',
      '我爱你到永远',
    ]);
    expect(result.noopReason, isNull);
  });

  test('ignores simplified/traditional differences by default', () {
    final result = plan(['我愛你', '我爱你'], '爱你', '想你');
    expect(result.changes.map((match) => match.after), ['我想你', '我想你']);

    final strict = plan(['我愛你', '我爱你'], '爱你', '想你', ignoreScript: false);
    expect(strict.changes.map((match) => match.index), [1]);
  });

  test('case folding and whole-word matching for Latin text', () {
    final folded = plan(['I LOVE you', 'lovely day'], 'love', 'need');
    expect(folded.changes.map((match) => match.after), [
      'I need you',
      'needly day',
    ]);

    final whole = plan(
      ['I LOVE you', 'lovely day'],
      'love',
      'need',
      wholeWord: true,
    );
    expect(whole.changes.map((match) => match.after), ['I need you']);

    final exact = plan(['I LOVE you'], 'love', 'need', ignoreCase: false);
    expect(exact.noopReason, LyricFindReplaceNoopReason.noMatches);
  });

  test('whole-word matching does not restrict CJK text', () {
    final result = plan(['我爱你'], '爱', '想', wholeWord: true);
    expect(result.changes.single.after, '我想你');
  });

  test('matches do not overlap', () {
    final result = plan(['啊啊啊'], '啊啊', '哦');
    expect(result.matches.single.ranges, [const LyricTextSpanRange(0, 2)]);
    expect(result.changes.single.after, '哦啊');
  });

  test('ranges are UTF-16 offsets even with surrogate pairs', () {
    final ranges = service.findRanges(
      '𠮷野家的爱',
      const LyricFindReplaceQuery(find: '爱', replacement: ''),
    );
    expect(ranges, [const LyricTextSpanRange(5, 6)]);
  });

  test('an empty replacement deletes the matched text', () {
    final result = plan(['我爱你呀', '呀呀'], '呀', '');
    expect(result.changes.map((match) => match.after), ['我爱你', '']);
  });

  test('explains why nothing would change', () {
    expect(
      plan(['我爱你'], '', 'x').noopReason,
      LyricFindReplaceNoopReason.emptyQuery,
    );
    expect(
      plan(['我爱你'], '恨', 'x').noopReason,
      LyricFindReplaceNoopReason.noMatches,
    );
    expect(
      plan(['我爱你'], '爱', '爱').noopReason,
      LyricFindReplaceNoopReason.replacementIdentical,
    );
    expect(
      plan(['我碍你'], '碍', '爱', protectedIndices: {0}).noopReason,
      LyricFindReplaceNoopReason.onlyProtectedLines,
    );
  });

  test('protected rows are listed but skipped unless opted in', () {
    final skipped = plan(['我碍你', '你碍我'], '碍', '爱', protectedIndices: {0});
    expect(skipped.matches, hasLength(2));
    expect(skipped.changes.map((match) => match.index), [1]);
    expect(skipped.protectedMatches.map((match) => match.index), [0]);

    final included = plan(
      ['我碍你', '你碍我'],
      '碍',
      '爱',
      protectedIndices: {0},
      includeProtected: true,
    );
    expect(included.changes.map((match) => match.index), [0, 1]);
  });

  test('applies only the selected rows and keeps timing and ids', () {
    final document = _doc(['我碍你', '你碍我', '他碍她']);
    final result = service.plan(
      document,
      query: const LyricFindReplaceQuery(find: '碍', replacement: '爱'),
    );
    final applied = result.applyTo(document, excludedIndices: {1});
    expect(applied.lines.map((line) => line.text), ['我爱你', '你碍我', '他爱她']);
    expect(applied.lines[2].id, 'l2');
    expect(applied.lines[2].startTime, document.lines[2].startTime);
    expect(result.selectedChanges({1}).map((match) => match.index), [0, 2]);
  });

  test('refuses to apply over a row that changed meanwhile', () {
    final document = _doc(['我碍你']);
    final result = service.plan(
      document,
      query: const LyricFindReplaceQuery(find: '碍', replacement: '爱'),
    );
    final edited = document.copyWith(
      lines: [document.lines.single.copyWith(text: '我碍他')],
    );
    expect(() => result.applyTo(edited), throwsStateError);
  });
}
