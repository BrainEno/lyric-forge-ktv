import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_states.dart';

Future<void> _pump(WidgetTester tester, Widget child, {Size? size}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('review queue empty state', () {
    testWidgets('after confirming rows it says how many', (tester) async {
      await _pump(tester, const LyricReviewQueueEmptyState(reviewedCount: 3));

      expect(find.text(LyricListStateText.queueDoneTitle), findsOneWidget);
      expect(find.textContaining('已确认 3 行'), findsOneWidget);
      expect(find.text(LyricListStateText.queueQuietTitle), findsNothing);
    });

    testWidgets('with nothing confirmed it explains the threshold', (
      tester,
    ) async {
      await _pump(tester, const LyricReviewQueueEmptyState(reviewedCount: 0));

      expect(find.text(LyricListStateText.queueQuietTitle), findsOneWidget);
      expect(find.textContaining('不能判断歌词语义'), findsOneWidget);
    });

    testWidgets('offers all lines only when the host can show them', (
      tester,
    ) async {
      await _pump(tester, const LyricReviewQueueEmptyState(reviewedCount: 0));
      expect(find.byKey(const ValueKey('lyric-list:show-all')), findsNothing);

      var shown = 0;
      await _pump(
        tester,
        LyricReviewQueueEmptyState(
          reviewedCount: 0,
          onShowAllLines: () => shown++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('lyric-list:show-all')));
      expect(shown, 1);
    });

    testWidgets('fits a phone with large text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: LyricReviewQueueEmptyState(
              reviewedCount: 12,
              onShowAllLines: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(LyricListStateText.showAll), findsOneWidget);
    });
  });

  group('filtered empty state', () {
    testWidgets('suggests another filter and offers all lines', (
      tester,
    ) async {
      var shown = 0;
      await _pump(tester, LyricFilteredEmptyState(onShowAllLines: () => shown++));

      expect(find.text(LyricListStateText.filteredTitle), findsOneWidget);
      expect(find.text(LyricListStateText.filteredMessage), findsOneWidget);
      await tester.tap(find.text(LyricListStateText.showAll));
      expect(shown, 1);
    });

    testWidgets('without a host action shows no button', (tester) async {
      await _pump(tester, const LyricFilteredEmptyState());

      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  testWidgets('search empty state says nothing matched', (tester) async {
    await _pump(tester, const LyricSearchEmptyState());

    expect(find.text(LyricListStateText.noMatch), findsOneWidget);
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
  });

  group('search field', () {
    testWidgets('reports typing and clears', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final typed = <String>[];
      var cleared = 0;
      var query = '';

      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => LyricListSearchField(
            controller: controller,
            query: query,
            onChanged: (value) {
              typed.add(value);
              setState(() => query = value);
            },
            onClear: () {
              cleared++;
              controller.clear();
              setState(() => query = '');
            },
          ),
        ),
      );

      expect(find.text(LyricListStateText.searchHint), findsOneWidget);
      expect(find.byTooltip(LyricListStateText.clearSearch), findsNothing);

      await tester.enterText(find.byType(TextField), '副歌');
      await tester.pump();
      expect(typed, ['副歌']);
      expect(find.byTooltip(LyricListStateText.clearSearch), findsOneWidget);

      await tester.tap(find.byTooltip(LyricListStateText.clearSearch));
      await tester.pump();
      expect(cleared, 1);
      expect(controller.text, isEmpty);
      expect(find.byTooltip(LyricListStateText.clearSearch), findsNothing);
    });

    testWidgets('uses the focus node it is given', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await _pump(
        tester,
        LyricListSearchField(
          controller: controller,
          focusNode: focusNode,
          query: '',
          onChanged: (_) {},
          onClear: () {},
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode,
        same(focusNode),
      );
      expect(focusNode.hasFocus, isTrue);
    });
  });

  testWidgets('candidate summary shows its text', (tester) async {
    await _pump(
      tester,
      const LyricCandidateSummary(text: '已保存候选 3 行', padding: 12),
      size: const Size(390, 600),
    );

    expect(find.text('已保存候选 3 行'), findsOneWidget);
    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.text('已保存候选 3 行'), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(12, 0, 12, 8));
  });
}
