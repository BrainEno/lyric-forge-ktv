import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_asr_loop_detector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricDocument doc(List<String> texts) => LyricDocument(
  language: 'en',
  lines: [
    for (var i = 0; i < texts.length; i++)
      LyricLine(
        text: texts[i],
        startTime: Duration(seconds: i * 3),
        endTime: Duration(seconds: i * 3 + 2),
        id: 'r$i',
      ),
  ],
);

List<String> cycle(List<String> block, int times) => [
  for (var i = 0; i < times; i++) ...block,
];

void main() {
  const detector = LyricAsrLoopDetector();
  const couplet = [
    'Driving through the rain tonight',
    'Driving through the rain',
  ];

  group('repeated blocks of rows', () {
    test('a couplet cycling over an interlude is one strong finding', () {
      // What the user saw: after the real verses, the same two lines over and
      // over, through the solo and the sung parts alike.
      final document = doc([
        'The first verse is sung here',
        'and the verse goes on',
        ...cycle(couplet, 12),
      ]);
      final plan = detector.plan(document);

      expect(plan.issues, hasLength(1));
      final issue = plan.issues.single;
      expect(issue.kind, LyricAsrLoopKind.repeatedBlock);
      expect(issue.index, 2);
      expect(issue.blockRows, 2);
      expect(issue.repeats, 12);
      expect(issue.runIndices, hasLength(24));
      expect(issue.strong, isTrue);
      // Two repetitions are kept, the other twenty rows go.
      expect(issue.removedIndices.first, 6);
      expect(issue.removedIndices, hasLength(20));
      expect(plan.defaultPositions, [0]);

      final fixed = plan.applyTo(document, plan.defaultPositions.toSet());
      expect(fixed.lines.map((line) => line.text), [
        'The first verse is sung here',
        'and the verse goes on',
        ...cycle(couplet, 2),
      ]);
      expect(detector.loopRowCount(document), 20);
    });

    test('punctuation and letter case do not hide the cycle', () {
      final document = doc([
        'Driving through the rain tonight.',
        'driving through the rain',
        'DRIVING THROUGH THE RAIN TONIGHT',
        'Driving, through the rain!',
        'Driving through the rain tonight',
        'Driving through the rain',
      ]);
      final issue = detector.plan(document).issues.single;
      expect(issue.kind, LyricAsrLoopKind.repeatedBlock);
      expect(issue.repeats, 3);
      // Three repetitions are listed for listening, not selected.
      expect(issue.strong, isFalse);
      expect(issue.removedIndices, [4, 5]);
    });

    test('a chorus sung twice in a row is not a loop', () {
      final document = doc([
        ...cycle(couplet, 2),
        'a new line follows',
        ...cycle(couplet, 2),
      ]);
      expect(detector.plan(document).issues, isEmpty);
    });

    test('three- and four-row blocks are found; the longest cover wins', () {
      final document = doc(
        cycle(['line one here', 'line two here', 'line three here'], 5),
      );
      final issue = detector.plan(document).issues.single;
      expect(issue.blockRows, 3);
      expect(issue.repeats, 5);
      expect(issue.removedIndices, hasLength(9));
    });

    test('identical rows stay a row run, not a block of two', () {
      final document = doc(List.filled(8, 'the same line again'));
      final issue = detector.plan(document).issues.single;
      expect(issue.kind, LyricAsrLoopKind.repeatedRows);
      expect(issue.blockRows, 1);
      expect(issue.repeats, 8);
    });

    test('hand-edited rows inside the cycle are kept', () {
      final document = doc(cycle(couplet, 4));
      final plan = detector.plan(document, protectedIndices: {6});
      final issue = plan.issues.single;
      expect(issue.removedIndices, [4, 5, 7]);
      expect(issue.fixable, isTrue);
    });

    test('a row inside a kept block can still loop on its own', () {
      final looping = List.filled(8, 'oh').join(' ');
      final document = doc(cycle([looping, 'second row here'], 4));
      final kinds = detector.plan(document).issues.map((issue) => issue.kind);
      expect(kinds.first, LyricAsrLoopKind.repeatedBlock);
      expect(
        kinds.where((kind) => kind == LyricAsrLoopKind.inRowRepeat),
        hasLength(2),
      );
    });

    test('draft health counts the rows the block fix removes', () {
      final health = const LyricDraftHealthService().analyze(
        doc(cycle(couplet, 6)),
      );
      expect(health.loopRows, 8);
      expect(health.hasIssues, isTrue);
    });
  });
}
