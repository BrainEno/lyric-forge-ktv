import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_repetition_consistency_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Synthetic lines written for these tests, not taken from a song.
LyricDocument _doc(List<String> texts, {List<int>? confidence}) =>
    LyricDocument(
      language: 'zh',
      lines: [
        for (final (index, text) in texts.indexed)
          LyricLine(
            id: 'l$index',
            text: text,
            startTime: Duration(seconds: index * 4),
            endTime: Duration(seconds: index * 4 + 3),
            confidence: confidence?[index] ?? 80,
            confidenceSource: confidence == null
                ? LyricConfidenceSource.unscored
                : LyricConfidenceSource.model,
          ),
      ],
    );

void main() {
  const service = LyricRepetitionConsistencyService();

  test('groups a misrecognised chorus repeat with the majority', () {
    final document = _doc([
      '夜空中最亮的星',
      '能否听清那仰望的人',
      '我想要拥抱你的温度',
      '夜空中最亮的星',
      '我想要拥抱你的温度',
      '夜空中最亮的心',
      '我想要拥抱你的温柔',
      '夜空中最亮的星',
    ]);
    final report = service.analyze(document);

    expect(report.groups, hasLength(2));
    final star = report.groups.first;
    expect(star.variants.map((variant) => variant.text), [
      '夜空中最亮的星',
      '夜空中最亮的心',
    ]);
    expect(star.variants.first.indices, [0, 3, 7]);
    expect(star.recommendation, LyricRepetitionRecommendation.majority);
    expect(star.recommendedVariant, 0);
    expect(star.selectedByDefault, isTrue);

    final warmth = report.groups[1];
    expect(warmth.variants.first.text, '我想要拥抱你的温度');
    expect(warmth.variants.first.count, 2);
    expect(warmth.selectedByDefault, isTrue);

    final changes = report.changesFor(document, {0: 0, 1: 0});
    expect(changes.map((change) => change.index), [5, 6]);
    final applied = LyricRepetitionReport.apply(document, changes);
    expect(applied.lines[5].text, '夜空中最亮的星');
    expect(applied.lines[6].text, '我想要拥抱你的温度');
    expect(applied.lines[5].startTime, document.lines[5].startTime);
    expect(applied.lines[5].id, 'l5');
  });

  test('ignores punctuation, case and script when grouping spellings', () {
    final report = service.analyze(_doc(['我愛你到永遠', '我爱你到永远。', '我碍你到永远']));
    final group = report.groups.single;
    expect(group.variants.first.count, 2);
    expect(group.variants.first.text, '我愛你到永遠');
    expect(group.variants[1].text, '我碍你到永远');
  });

  test('short rows and clearly different rows are not grouped', () {
    final report = service.analyze(
      _doc(['啊啊啊', '哦哦哦', '我们一起唱', '你们都离开', '我们一起唱']),
    );
    expect(report.groups, isEmpty);
    expect(report.comparedRows, 3);
  });

  test('two recurring spellings are offered but not pre-selected', () {
    final report = service.analyze(
      _doc(['想你的夜晚很长', '想我的夜晚很长', '想你的夜晚很长', '想我的夜晚很长', '想你的夜晚很长']),
    );
    final group = report.groups.single;
    expect(group.recommendation, LyricRepetitionRecommendation.majority);
    expect(group.variants.first.count, 3);
    // 2 is more than half of 3: likely deliberate, the user decides.
    expect(group.selectedByDefault, isFalse);
  });

  test('a tie without confidence is undecided', () {
    final group = service.analyze(_doc(['夜空中最亮的星', '夜空中最亮的心'])).groups.single;
    expect(group.recommendation, LyricRepetitionRecommendation.undecided);
    expect(group.recommendedVariant, isNull);
    expect(group.selectedByDefault, isFalse);
  });

  test('confidence breaks a tie but is never pre-selected', () {
    final group = service
        .analyze(_doc(['夜空中最亮的星', '夜空中最亮的心'], confidence: [55, 92]))
        .groups
        .single;
    expect(
      group.recommendation,
      LyricRepetitionRecommendation.higherConfidence,
    );
    expect(group.recommended!.text, '夜空中最亮的心');
    expect(group.selectedByDefault, isFalse);

    final close = service
        .analyze(_doc(['夜空中最亮的星', '夜空中最亮的心'], confidence: [85, 90]))
        .groups
        .single;
    expect(close.recommendation, LyricRepetitionRecommendation.undecided);
  });

  test('a manually confirmed spelling beats the majority', () {
    final document = _doc(['夜空中最亮的心', '夜空中最亮的心', '夜空中最亮的星']);
    final report = service.analyze(document, protectedIndices: {2});
    final group = report.groups.single;
    expect(
      group.recommendation,
      LyricRepetitionRecommendation.manuallyConfirmed,
    );
    expect(group.recommended!.text, '夜空中最亮的星');
    expect(group.selectedByDefault, isTrue);
    expect(
      report
          .changesFor(document, {0: group.recommendedVariant!})
          .map((change) => change.index),
      [0, 1],
    );
  });

  test('protected outliers are skipped unless opted in', () {
    final document = _doc(['夜空中最亮的星', '夜空中最亮的星', '夜空中最亮的心', '夜空中最亮的心']);
    final report = service.analyze(document, protectedIndices: {3});
    // Row 3 is protected, so its spelling is the confirmed one.
    final group = report.groups.single;
    expect(group.recommended!.text, '夜空中最亮的心');

    final towardsMajority = report.changesFor(document, {
      0: group.variants.indexWhere((v) => v.text == '夜空中最亮的星'),
    });
    expect(towardsMajority.map((change) => change.index), [2]);
    final withProtected = report.changesFor(document, {
      0: group.variants.indexWhere((v) => v.text == '夜空中最亮的星'),
    }, includeProtected: true);
    expect(withProtected.map((change) => change.index), [2, 3]);
  });

  test(
    'more than one confirmed spelling means the variation is deliberate',
    () {
      final group = service
          .analyze(
            _doc(['夜空中最亮的星', '夜空中最亮的心', '夜空中最亮的星']),
            protectedIndices: {0, 1},
          )
          .groups
          .single;
      expect(group.recommendation, LyricRepetitionRecommendation.undecided);
    },
  );

  test('clusters around the seed, not by chaining', () {
    // A and C differ by two characters (too far), each is one away from B.
    final report = service.analyze(
      _doc(['一二三四五六', '一二三四五六', '一二三四五七', '一二三四八七']),
    );
    final group = report.groups.single;
    expect(group.variants.map((variant) => variant.text), ['一二三四五六', '一二三四五七']);
  });

  test('bounded edit distance', () {
    List<int> runes(String text) => text.runes.toList();
    expect(
      LyricRepetitionConsistencyService.boundedEditDistance(
        runes('夜空中最亮的星'),
        runes('夜空中最亮的心'),
        1,
      ),
      1,
    );
    expect(
      LyricRepetitionConsistencyService.boundedEditDistance(
        runes('abcdef'),
        runes('abXdeY'),
        1,
      ),
      isNull,
    );
    expect(
      LyricRepetitionConsistencyService.boundedEditDistance(
        runes('kitten'),
        runes('sitting'),
        3,
      ),
      3,
    );
    expect(
      LyricRepetitionConsistencyService.boundedEditDistance(
        runes('我爱你一万年'),
        runes('爱你一万年'),
        1,
      ),
      1,
    );
  });
}
