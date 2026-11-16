import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_structure_advisor.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
void main() {
  const advisor = LyricStructureAdvisor();
  const longLine = '夜空中最亮的星能否听清 那仰望的人心底的孤独和叹息';

  LyricLine line(String text, int startMs, int endMs, {String? id}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        id: id,
      );

  LyricDocument document(
    List<LyricLine> lines, {
    Map<String, dynamic> metadata = const {},
  }) => LyricDocument(language: 'zh', lines: lines, metadata: metadata);

  final mixed = document([
    line(longLine, 0, 6000, id: 'long'),
    line('夜空中最亮的星', 6000, 9000, id: 'a'),
    line('啊', 9100, 9500, id: 'frag'),
    line('能否听清', 12000, 14000, id: 'c'),
  ]);

  group('analyze', () {
    test('suggests splitting an over-long row at its natural break', () {
      final plan = advisor.analyze(mixed);
      final split = plan.suggestions.first;
      expect(split.kind, LyricStructureSuggestionKind.splitLongLine);
      expect(split.index, 0);
      expect(split.after, ['夜空中最亮的星能否听清', '那仰望的人心底的孤独和叹息']);
      expect(split.confident, isTrue);
      // 11 of 24 sung characters fall before the break.
      expect(split.splitTime, const Duration(milliseconds: 2750));
    });

    test('suggests merging a fragment into the closer neighbour', () {
      final plan = advisor.analyze(mixed);
      expect(plan.splitCount, 1);
      expect(plan.mergeCount, 1);
      final merge = plan.suggestions[1];
      expect(merge.kind, LyricStructureSuggestionKind.mergeFragment);
      expect(merge.index, 1);
      expect(merge.before, ['夜空中最亮的星', '啊']);
      expect(merge.after, ['夜空中最亮的星啊']);
      expect(merge.affectedIndices, [1, 2]);
    });

    test('a long row without any break is suggested but not pre-selected', () {
      final plan = advisor.analyze(
        document([line('一二三四五六七八九十一二三四五六七八九十一', 0, 8000)]),
      );
      expect(plan.splitCount, 1);
      expect(plan.suggestions.single.confident, isFalse);
    });

    test('a fragment separated by a long pause is left alone', () {
      final plan = advisor.analyze(
        document([
          line('夜空中最亮的星', 0, 3000),
          line('啊', 4000, 4400),
          line('能否听清', 6000, 8000),
        ]),
      );
      expect(plan.isEmpty, isTrue);
    });

    test('does not merge when the result would be too long', () {
      final plan = advisor.analyze(
        document([
          line('一二三四五六七八九十一二三四五六七八九十', 0, 6000),
          line('啊', 6100, 6400),
        ]),
      );
      expect(plan.mergeCount, 0);
    });

    test('skips hand-edited rows and reports them', () {
      final plan = advisor.analyze(mixed, protectedIndices: {0, 2});
      expect(plan.isEmpty, isTrue);
      expect(plan.skippedProtectedIndices, containsAll([0, 1, 2]));
    });

    test('never touches a 建议补入 row', () {
      final withSuggestion = document(
        mixed.lines,
        metadata: {
          SecondaryOnlySuggestion.metadataKey: SecondaryOnlySuggestion.wrap([
            const SecondaryOnlySuggestion(text: '啊', startMs: 9100, endMs: 9500),
          ]),
        },
      );
      final plan = advisor.analyze(withSuggestion);
      expect(plan.mergeCount, 0);
      expect(plan.splitCount, 1);
    });

    test('never merges caption or annotation rows into a lyric', () {
      final plan = advisor.analyze(
        document([line('夜空中最亮的星', 0, 3000), line('[音乐]', 3100, 3400)]),
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('applyTo', () {
    test('applies every selected suggestion in one pass', () {
      final plan = advisor.analyze(mixed);
      final after = plan.applyTo(mixed, {0, 1});
      expect(after.lines.map((l) => l.text), [
        '夜空中最亮的星能否听清',
        '那仰望的人心底的孤独和叹息',
        '夜空中最亮的星啊',
        '能否听清',
      ]);
      expect(after.lines[0].id, 'long');
      expect(after.lines[1].id, isNotNull);
      expect(after.lines[1].id, isNot('long'));
      expect(after.lines[2].id, 'a');
      expect(after.lines[2].endTime, const Duration(milliseconds: 9500));
      expect(plan.selectionAfterApply({0, 1}), 0);
    });

    test('applies only the selected suggestions', () {
      final plan = advisor.analyze(mixed);
      final after = plan.applyTo(mixed, {1});
      expect(after.lines, hasLength(3));
      expect(after.lines.first.text, longLine);
      expect(after.lines[1].text, '夜空中最亮的星啊');
      expect(plan.selectionAfterApply({1}), 1);
      expect(identical(plan.applyTo(mixed, {}), mixed), isTrue);
    });

    test('keeps evidence on untouched rows and drops it on changed rows', () {
      final withCandidates = document(
        mixed.lines,
        metadata: {
          LyricIndexedReviewMetadata.candidatesKey: [
            {'lineIndex': 0, 'alternativeText': 'x'},
            {'lineIndex': 1, 'alternativeText': 'y'},
            {'lineIndex': 3, 'alternativeText': 'z'},
          ],
          LyricIndexedReviewMetadata.candidateCountKey: 3,
        },
      );
      final plan = advisor.analyze(withCandidates);
      final after = plan.applyTo(withCandidates, {0, 1});
      final candidates =
          after.metadata[LyricIndexedReviewMetadata.candidatesKey] as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['lineIndex'], 3);
      expect((candidates.single as Map)['alternativeText'], 'z');
      expect(after.metadata[LyricIndexedReviewMetadata.candidateCountKey], 1);
    });
  });

  group('LyricDraftHealthService', () {
    test('counts what each batch tool would offer', () {
      final health = const LyricDraftHealthService().analyze(
        document([
          line('夜空中最亮的星', 0, 3000),
          line('能否听清那仰望的人', 4000, 7000),
          line('夜空中最亮的星', 8000, 11000),
          line('夜空中最亮的心', 12000, 15000),
          line('[音乐]', 16000, 19000),
          line('字幕由Amara.org社区提供', 20000, 23000),
          line(longLine, 24000, 30000),
        ]),
      );
      expect(health.captionRows, 2);
      expect(health.repetitionGroups, 1);
      expect(health.longLines, 1);
      expect(health.fragments, 0);
      expect(health.structureIssues, 1);
      expect(health.hasIssues, isTrue);
    });

    test('a clean draft has no issues and an empty one is clean', () {
      const service = LyricDraftHealthService();
      final clean = service.analyze(
        document([line('夜空中最亮的星', 0, 3000), line('能否听清', 4000, 6000)]),
      );
      expect(clean.hasIssues, isFalse);
      expect(service.analyze(document(const [])).hasIssues, isFalse);
    });

    test('memoises per document instance', () {
      const service = LyricDraftHealthService();
      final doc = document([line('夜空中最亮的星', 0, 3000)]);
      expect(identical(service.cached(doc), service.cached(doc)), isTrue);
    });
  });
}
