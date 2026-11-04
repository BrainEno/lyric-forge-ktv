import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  late List<int> selected;

  setUp(() => selected = <int>[]);

  Widget host({
    required LyricDocument document,
    required List<int> visibleIndices,
    LyricReviewFilter filter = LyricReviewFilter.all,
    Map<int, LyricReviewPriority> priorities = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: LyricListPane(
            document: document,
            visibleIndices: visibleIndices,
            reviewPriorityByIndex: priorities,
            filter: filter,
            activeAuditionLineIndex: null,
            auditionPlaying: false,
            selectedIndex: null,
            currentPlaybackLine: null,
            followPlayback: false,
            focusRequestId: 0,
            focusLineIndex: null,
            fallbackCandidateFor: (_) => null,
            onPreviewLine: null,
            onInsertedLineFocus: (_) {},
            onSelectLine: selected.add,
            onUpdateLine: (_, _) {},
            onDeleteLine: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('按 visibleIndices 渲染歌词行', (tester) async {
    await tester.pumpWidget(
      host(document: _document(3), visibleIndices: [0, 1, 2]),
    );

    expect(find.text('第 1 行'), findsOneWidget);
    expect(find.text('第 2 行'), findsOneWidget);
    expect(find.text('第 3 行'), findsOneWidget);
  });

  testWidgets('review priority tooltip maps stable reason codes to UI labels', (
    tester,
  ) async {
    final priority = LyricReviewPriority(
      lineIndex: 0,
      score: 60,
      reasons: const [
        LyricReviewPriorityReason(LyricReviewPriorityReasonCode.emptyLyrics),
      ],
    );

    await tester.pumpWidget(
      host(
        document: _document(1),
        visibleIndices: const [0],
        priorities: {0: priority},
      ),
    );

    expect(find.byTooltip('歌词为空'), findsOneWidget);
  });

  testWidgets('点击行会请求选中该行', (tester) async {
    await tester.pumpWidget(
      host(document: _document(3), visibleIndices: [0, 1, 2]),
    );

    await tester.tap(find.text('第 2 行'));
    // The row also handles double-tap and long-press, so a single tap only
    // resolves after the double-tap timeout.
    await tester.pump(const Duration(milliseconds: 400));

    expect(selected, <int>[1]);
  });

  testWidgets('筛选后没有待复核行时说明复核已完成', (tester) async {
    await tester.pumpWidget(
      host(
        document: _document(3),
        visibleIndices: const [],
        filter: LyricReviewFilter.needsReview,
      ),
    );

    expect(find.text('暂未发现明显风险行'), findsOneWidget);
  });

  testWidgets('没有可见行但不是复核筛选时给出筛选空状态', (tester) async {
    await tester.pumpWidget(
      host(document: _document(3), visibleIndices: const []),
    );

    expect(find.text('当前筛选下没有待处理歌词'), findsOneWidget);
  });

  testWidgets('超过 8 行时提供搜索框，可过滤到匹配行', (tester) async {
    final document = _document(
      10,
      texts: [
        for (var index = 0; index < 10; index++)
          index == 7 ? '唯一的一段副歌' : '普通第 $index 行',
      ],
    );
    await tester.pumpWidget(
      host(
        document: document,
        visibleIndices: List<int>.generate(10, (i) => i),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '副歌');
    await tester.pump();

    expect(find.text('唯一的一段副歌'), findsOneWidget);
    expect(find.text('普通第 0 行'), findsNothing);
  });
}

LyricDocument _document(int count, {List<String>? texts}) {
  return LyricDocument(
    language: 'zh',
    lines: [
      for (var index = 0; index < count; index++)
        LyricLine(
          id: 'line-$index',
          text: texts?[index] ?? '第 ${index + 1} 行',
          startTime: Duration(milliseconds: index * 4000),
          endTime: Duration(milliseconds: index * 4000 + 3000),
        ),
    ],
  );
}
