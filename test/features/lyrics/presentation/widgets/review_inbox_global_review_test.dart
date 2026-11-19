import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/review_inbox_bulk_review.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/review_inbox_global_review.dart';

void main() {
  group('ReviewInboxGlobalReviewText', () {
    test('lists a few project names in full', () {
      expect(ReviewInboxGlobalReviewText.names(['夜曲']), '「夜曲」');
      expect(
        ReviewInboxGlobalReviewText.names(['夜曲', '晴天', '稻香']),
        '「夜曲」「晴天」「稻香」',
      );
    });

    test('shortens a long list to the first names and a count', () {
      expect(
        ReviewInboxGlobalReviewText.names(['夜曲', '晴天', '稻香', '七里香', '告白气球']),
        '「夜曲」「晴天」「稻香」等 5 个工程',
      );
    });

    test('progress counts projects', () {
      expect(ReviewInboxGlobalReviewText.progress(3, 8), '正在标记第 3/8 个工程…');
    });

    test('a complete undo says how many projects came back', () {
      const undo = BulkReviewBatchUndo(restored: 3, conflicts: 0, failed: 0);

      expect(
        ReviewInboxGlobalReviewText.undoResult(undo),
        '已撤销，3 个工程的复核标记恢复原样',
      );
    });

    test('a partial undo names what was left alone', () {
      const undo = BulkReviewBatchUndo(restored: 1, conflicts: 2, failed: 1);

      expect(
        ReviewInboxGlobalReviewText.undoResult(undo),
        '已撤销 1 个工程；2 个工程已有新的改动，没有撤销；1 个工程没能恢复，请稍后再试',
      );
    });
  });

  group('ReviewInboxSummaryBar', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: child)),
    );

    testWidgets('shows the summary and the button when work is waiting', (
      tester,
    ) async {
      var pressed = 0;
      await tester.pumpWidget(
        host(
          ReviewInboxSummaryBar(
            summary: '3 个工程，共 12 行待复核',
            onMarkEverything: () => pressed++,
          ),
        ),
      );

      expect(find.text('3 个工程，共 12 行待复核'), findsOneWidget);
      final button = find.byKey(ReviewInboxSummaryBar.buttonKey);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(40));

      await tester.tap(button);
      expect(pressed, 1);
    });

    testWidgets('hides the button when nothing waits', (tester) async {
      await tester.pumpWidget(
        host(
          const ReviewInboxSummaryBar(
            summary: '2 个工程，暂时没有待复核的行',
            onMarkEverything: null,
          ),
        ),
      );

      expect(find.byKey(ReviewInboxSummaryBar.buttonKey), findsNothing);
      expect(find.text('2 个工程，暂时没有待复核的行'), findsOneWidget);
    });

    testWidgets('replaces the button with announced progress while running', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ReviewInboxSummaryBar(
            summary: '4 个工程，共 9 行待复核',
            onMarkEverything: () {},
            progress: (done: 1, total: 4),
          ),
        ),
      );

      expect(find.byKey(ReviewInboxSummaryBar.buttonKey), findsNothing);
      expect(find.byKey(ReviewInboxSummaryBar.progressKey), findsOneWidget);
      final progressText = find.text('正在标记第 1/4 个工程…');
      expect(progressText, findsOneWidget);
      final announcer = tester.widget<Semantics>(
        find.ancestor(of: progressText, matching: find.byType(Semantics)).first,
      );
      expect(announcer.properties.liveRegion, isTrue);
      expect(announcer.container, isTrue);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.25, 0.001));
      expect(bar.color, AppColors.accent);
    });
  });

  testWidgets('the confirmation offers cancel and confirm', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<bool>(
                context: context,
                builder: (_) => const ReviewInboxGlobalReviewDialog(
                  projectNames: ['夜曲', '晴天'],
                  totalLines: 20,
                  pendingLines: 7,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('把 2 个工程全部标为已复核？'), findsOneWidget);
    expect(find.text('「夜曲」「晴天」'), findsOneWidget);

    await tester.tap(find.text(ReviewInboxGlobalReviewText.confirmLabel));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
