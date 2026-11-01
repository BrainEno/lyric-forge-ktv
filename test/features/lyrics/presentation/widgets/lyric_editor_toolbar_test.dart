import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _document = LyricDocument(
  language: 'zh',
  lines: [
    LyricLine(
      text: '月亮代表我的心',
      startTime: Duration(seconds: 1),
      endTime: Duration(seconds: 5),
    ),
    LyricLine(
      text: '今天天气真好',
      startTime: Duration(seconds: 5),
      endTime: Duration(seconds: 9),
    ),
  ],
  globalOffset: Duration(milliseconds: 200),
);

/// Counts the controls a user can actually press, which is the number the review
/// measured when it complained about a toolbar with twenty-five of them.
Finder get _interactiveControls => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton ||
      widget is FilterChip ||
      widget is ChoiceChip ||
      widget is FilledButton ||
      widget is OutlinedButton ||
      widget is TextButton,
);

void _noop() {}

void main() {
  late List<String> calls;
  late LyricReviewFilter selectedFilter;
  late Duration updatedOffset;

  setUp(() {
    calls = <String>[];
    selectedFilter = LyricReviewFilter.all;
    updatedOffset = Duration.zero;
  });

  Widget buildToolbar({
    LyricReviewFilter filter = LyricReviewFilter.all,
    bool followPlayback = true,
    VoidCallback? onProofreadV2 = _noop,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LyricEditorToolbar(
          document: _document,
          playback: const PlaybackState.idle(),
          playbackBelongsToProject: false,
          lowConfidenceCount: 1,
          reviewCount: 3,
          smartReviewCount: 4,
          filter: filter,
          onFilterChanged: (value) => selectedFilter = value,
          loopCurrentLineAudition: false,
          onLoopCurrentLineAuditionChanged: (_) {},
          followPlayback: followPlayback,
          onFollowPlaybackChanged: (_) {},
          onUpdateOffset: (value) => updatedOffset = value,
          onTogglePlayback: () => calls.add('play'),
          onSeekPlayback: (_) {},
          onReferenceAlignment: null,
          onReferenceProofread: null,
          onProofreadV2: onProofreadV2,
          onUndoReferenceAlignment: null,
          onViewAlignmentComparison: null,
          onRestoreAlignment: null,
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('默认只留少数几个控件，其余收进菜单', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));

    // play, filter, follow, offset, proofread menu
    expect(tester.widgetList(_interactiveControls).length, 5);
    expect(find.byType(ChoiceChip), findsNothing);
    // Read-only counts are text, not controls.
    expect(find.text('待复核 3'), findsOneWidget);
    expect(find.text('低置信度 1'), findsOneWidget);
    expect(find.text('2 行'), findsOneWidget);
    expect(find.text('ZH'), findsOneWidget);
  });

  testWidgets('紧凑宽度不再横向滚动，也不重复显示校对菜单', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(390, 844));

    // The old layout scrolled horizontally with no scrollbar, so anything on the
    // right was unreachable. A Wrap never hides a control.
    expect(
      find.descendant(
        of: find.byType(LyricEditorToolbar),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    // The app bar carries the proofreading menu on narrow layouts.
    expect(find.text('校对'), findsNothing);
    // play, filter, follow, offset
    expect(tester.widgetList(_interactiveControls).length, 4);
  });

  testWidgets('筛选菜单保留每种筛法的计数', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    Finder inMenu(String label) => find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text(label),
    );

    expect(inMenu('待复核 3'), findsOneWidget);
    expect(inMenu('低置信度 1'), findsOneWidget);
    expect(inMenu('智能复核 4'), findsOneWidget);
    expect(find.text('按低置信度、双引擎分歧与时间轴异常排序'), findsOneWidget);

    await tester.tap(inMenu('低置信度 1'));
    await tester.pumpAndSettle();
    expect(selectedFilter, LyricReviewFilter.lowConfidence);
  });

  testWidgets('偏移按钮显示当前值，并按 100ms 步进', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));

    expect(find.text('偏移 +0.2s'), findsOneWidget);

    await tester.tap(find.text('偏移 +0.2s'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前 100ms'));
    await tester.pumpAndSettle();

    expect(updatedOffset, const Duration(milliseconds: 100));
  });

  testWidgets('偏移归零项在无偏移时不可点', (tester) async {
    await pumpAt(
      tester,
      MaterialApp(
        home: Scaffold(
          body: LyricEditorToolbar(
            document: const LyricDocument(
              language: 'zh',
              lines: [
                LyricLine(
                  text: '月亮代表我的心',
                  startTime: Duration(seconds: 1),
                  endTime: Duration(seconds: 5),
                ),
              ],
            ),
            playback: const PlaybackState.idle(),
            playbackBelongsToProject: false,
            lowConfidenceCount: 0,
            reviewCount: 0,
            smartReviewCount: 0,
            filter: LyricReviewFilter.all,
            onFilterChanged: (_) {},
            loopCurrentLineAudition: false,
            onLoopCurrentLineAuditionChanged: (_) {},
            followPlayback: true,
            onFollowPlaybackChanged: (_) {},
            onUpdateOffset: (value) => updatedOffset = value,
            onTogglePlayback: () {},
            onSeekPlayback: (_) {},
            onReferenceAlignment: null,
            onReferenceProofread: null,
            onProofreadV2: null,
            onUndoReferenceAlignment: null,
            onViewAlignmentComparison: null,
            onRestoreAlignment: null,
          ),
        ),
      ),
      const Size(1280, 900),
    );

    expect(find.text('偏移 0ms'), findsOneWidget);
    await tester.tap(find.text('偏移 0ms'));
    await tester.pumpAndSettle();

    final reset = tester.widget<MenuItemButton>(
      find.ancestor(of: find.text('归零'), matching: find.byType(MenuItemButton)),
    );
    expect(reset.onPressed, isNull);
    expect(find.text('当前无偏移'), findsOneWidget);
  });

  testWidgets('循环本行只在智能复核下出现', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));
    expect(find.text('循环本行'), findsNothing);

    await pumpAt(
      tester,
      buildToolbar(filter: LyricReviewFilter.smartReview),
      const Size(1280, 900),
    );
    expect(find.text('循环本行'), findsOneWidget);
  });

  testWidgets('更多的三个入口按可用性出现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LyricEditorOverflowMenu(
                canExport: true,
                onExport: () => calls.add('export'),
                onInsertAtPlayback: null,
                onOpenPlayer: () => calls.add('player'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    // 插入 stays visible but disabled, so the user learns why instead of
    // wondering where the button went.
    final insert = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('在播放位置插入'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(insert.onPressed, isNull);
    expect(find.text('先试听本工程'), findsOneWidget);

    await tester.tap(find.text('导出 LRC'));
    await tester.pumpAndSettle();
    expect(calls, contains('export'));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整播放器'));
    await tester.pumpAndSettle();
    expect(calls, contains('player'));
  });
}
