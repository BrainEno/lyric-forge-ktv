import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/auto_proofread_dialogs.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_actions.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_review_controls.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_dialog.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/seekable_progress_bar.dart';
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

/// A queue whose counts are fixed by hand, so the widget assertions do not
/// depend on the priority heuristics.
LyricReviewQueue _queue({
  int needsReview = 3,
  int lowConfidence = 1,
  int totalLines = 2,
  int scoredLines = 2,
}) {
  final items = <LyricReviewPriority>[
    for (var index = 0; index < needsReview; index++)
      LyricReviewPriority(
        lineIndex: index,
        score: 40 - index,
        reasons: const [
          LyricReviewPriorityReason(LyricReviewPriorityReasonCode.emptyLyrics),
        ],
      ),
  ];
  return LyricReviewQueue(
    items: items,
    lowConfidenceIndices: {
      for (var index = 0; index < lowConfidence; index++) index,
    },
    totalLines: totalLines,
    scoredLines: scoredLines,
    reviewedLines: 0,
    confidenceThreshold: 70,
  );
}

void _noop() {}

/// The review group the editor passes, built around a hand-made queue.
LyricReviewControls _review({
  LyricReviewQueue? queue,
  LyricReviewFilter filter = LyricReviewFilter.all,
  bool followPlayback = true,
  ValueChanged<LyricReviewFilter>? onFilterChanged,
  ValueChanged<bool>? onFollowPlaybackChanged,
}) {
  final effective = queue ?? _queue();
  return LyricReviewControls(
    queue: effective,
    priorityByIndex: effective.byIndex,
    filter: filter,
    selectedLineIndex: null,
    followPlayback: followPlayback,
    onFilterChanged: onFilterChanged ?? (_) {},
    onFollowPlaybackChanged: onFollowPlaybackChanged ?? (_) {},
    onSelectLine: (_) {},
    onDecision: (_, _) {},
  );
}

/// A player that holds another song unless [ours] is set.
LyricPlaybackControls _player({
  bool ours = false,
  bool playing = false,
  VoidCallback? onToggle,
}) {
  return LyricPlaybackControls(
    state: const PlaybackState.idle().copyWith(isPlaying: playing),
    belongsToProject: ours,
    onSeek: (_) {},
    onToggle: onToggle ?? () {},
  );
}

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
    LyricReviewQueue? review,
    LyricReviewFilter filter = LyricReviewFilter.all,
    bool followPlayback = true,
    LyricProofreadActions proofread = const LyricProofreadActions(
      onSmartProofread: _noop,
    ),
    bool loopCurrentLine = false,
    ValueChanged<bool>? onLoopChanged,
    LyricPlaybackControls? player,
    ValueChanged<bool>? onFollowChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LyricEditorToolbar(
          document: _document,
          player: player ?? _player(onToggle: () => calls.add('play')),
          review: _review(
            queue: review,
            filter: filter,
            followPlayback: followPlayback,
            onFilterChanged: (value) => selectedFilter = value,
            onFollowPlaybackChanged: onFollowChanged,
          ),
          onUpdateOffset: (value) => updatedOffset = value,
          audition: LyricAuditionControls(
            onPreviewLine: (_) {},
            loopCurrentLine: loopCurrentLine,
            onLoopCurrentLineChanged: onLoopChanged ?? (_) {},
          ),
          proofread: proofread,
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
    expect(find.text('2 行'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
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

  testWidgets('一个「建议复核」开关取代了全部 / 待复核 / 低置信度菜单', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));

    // One number, on the chip; no menu, no second spelling of the queue.
    expect(find.text('建议复核 3'), findsOneWidget);
    expect(find.textContaining('待复核'), findsNothing);
    expect(find.textContaining('低置信度'), findsNothing);
    expect(find.text('全部'), findsNothing);
    expect(find.byIcon(Icons.filter_list_rounded), findsNothing);

    await tester.tap(find.byKey(LyricSuggestedReviewChip.chipKey));
    await tester.pumpAndSettle();
    expect(selectedFilter, LyricReviewFilter.suggested);
  });

  testWidgets('开着时再点一次回到全部歌词', (tester) async {
    await pumpAt(
      tester,
      buildToolbar(filter: LyricReviewFilter.suggested),
      const Size(1280, 900),
    );

    final chip = tester.widget<FilterChip>(
      find.byKey(LyricSuggestedReviewChip.chipKey),
    );
    expect(chip.selected, isTrue);
    expect(chip.tooltip, startsWith('正在只看建议复核的行；再点一次回到全部歌词'));

    selectedFilter = LyricReviewFilter.suggested;
    await tester.tap(find.byKey(LyricSuggestedReviewChip.chipKey));
    await tester.pumpAndSettle();
    expect(selectedFilter, LyricReviewFilter.all);
  });

  testWidgets('提示里按必看 / 留意分层，并列出主要原因', (tester) async {
    final queue = LyricReviewQueue(
      items: const [
        LyricReviewPriority(
          lineIndex: 4,
          score: 70,
          reasons: [
            LyricReviewPriorityReason(
              LyricReviewPriorityReasonCode.enginesDifferGreatly,
            ),
            LyricReviewPriorityReason(
              LyricReviewPriorityReasonCode.confidenceVeryLow,
              confidence: 31,
            ),
          ],
        ),
        LyricReviewPriority(
          lineIndex: 1,
          score: 30,
          reasons: [
            LyricReviewPriorityReason(
              LyricReviewPriorityReasonCode.enginesDifferClearly,
            ),
          ],
        ),
        LyricReviewPriority(
          lineIndex: 2,
          score: 20,
          reasons: [
            LyricReviewPriorityReason(
              LyricReviewPriorityReasonCode.overlapsNext,
            ),
          ],
        ),
      ],
      lowConfidenceIndices: const {4},
      totalLines: 8,
      scoredLines: 8,
      reviewedLines: 0,
      confidenceThreshold: 70,
    );

    await pumpAt(tester, buildToolbar(review: queue), const Size(1280, 900));

    final chip = tester.widget<FilterChip>(
      find.byKey(LyricSuggestedReviewChip.chipKey),
    );
    // A low score is one reason among others, not a second filter.
    expect(
      chip.tooltip,
      '只看建议复核的 3 行，最要紧的排在前面\n'
      '必看 1 · 留意 2\n'
      '主要原因：双引擎分歧 2、时间轴异常 1、置信度低 1',
    );
    // Strong evidence colours the icon as a caution.
    final icon = tester.widget<Icon>(find.byIcon(Icons.fact_check_outlined));
    expect(icon.color, AppColors.warning);
  });

  testWidgets('未评分的稿子在提示里说明只按结构证据排序', (tester) async {
    final unscored = LyricReviewQueue(
      items: const [
        LyricReviewPriority(
          lineIndex: 0,
          score: 40,
          reasons: [
            LyricReviewPriorityReason(
              LyricReviewPriorityReasonCode.enginesDifferClearly,
            ),
          ],
        ),
      ],
      lowConfidenceIndices: const <int>{},
      totalLines: 42,
      scoredLines: 0,
      reviewedLines: 0,
      confidenceThreshold: 70,
    );

    await pumpAt(tester, buildToolbar(review: unscored), const Size(1280, 900));

    expect(find.text('建议复核 1'), findsOneWidget);
    // Say "unknown", not a red "低置信度 0".
    expect(find.text('未评分 42'), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.byKey(LyricSuggestedReviewChip.chipKey),
    );
    expect(chip.tooltip, endsWith('本稿的识别引擎没有返回分数，只按结构与时间轴证据排序'));
    final icon = tester.widget<Icon>(find.byIcon(Icons.fact_check_outlined));
    expect(icon.color, isNull);
  });

  testWidgets('队列为空时开关停用，但开着时仍能关掉', (tester) async {
    final empty = _queue(needsReview: 0, lowConfidence: 0);
    await pumpAt(tester, buildToolbar(review: empty), const Size(1280, 900));

    var chip = tester.widget<FilterChip>(
      find.byKey(LyricSuggestedReviewChip.chipKey),
    );
    expect(find.text('建议复核 0'), findsOneWidget);
    expect(chip.onSelected, isNull);
    expect(chip.tooltip, '暂未发现需要复核的行');

    await pumpAt(
      tester,
      buildToolbar(review: empty, filter: LyricReviewFilter.suggested),
      const Size(1280, 900),
    );
    chip = tester.widget<FilterChip>(
      find.byKey(LyricSuggestedReviewChip.chipKey),
    );
    expect(chip.onSelected, isNotNull);
    selectedFilter = LyricReviewFilter.suggested;
    await tester.tap(find.byKey(LyricSuggestedReviewChip.chipKey));
    await tester.pumpAndSettle();
    expect(selectedFilter, LyricReviewFilter.all);
  });

  testWidgets('偏移按钮显示当前值，并按 100ms 步进', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));

    expect(find.text('偏移 +200ms'), findsOneWidget);

    await tester.tap(find.text('偏移 +200ms'));
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
            player: _player(),
            review: _review(
              queue: _queue(needsReview: 0, lowConfidence: 0, totalLines: 1),
            ),
            onUpdateOffset: (value) => updatedOffset = value,
            audition: LyricAuditionControls(
              onPreviewLine: (_) {},
              onLoopCurrentLineChanged: (_) {},
            ),
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

  testWidgets('循环本行只在建议复核列表下出现', (tester) async {
    await pumpAt(tester, buildToolbar(), const Size(1280, 900));
    expect(find.text('循环本行'), findsNothing);

    await pumpAt(
      tester,
      buildToolbar(filter: LyricReviewFilter.suggested),
      const Size(1280, 900),
    );
    expect(find.text('循环本行'), findsOneWidget);
  });

  testWidgets('循环本行开关读写试听分组', (tester) async {
    bool? toggled;
    await pumpAt(
      tester,
      buildToolbar(
        filter: LyricReviewFilter.suggested,
        loopCurrentLine: true,
        onLoopChanged: (value) => toggled = value,
      ),
      const Size(1280, 900),
    );

    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('循环本行'), matching: find.byType(FilterChip)),
    );
    expect(chip.selected, isTrue);

    await tester.tap(find.text('循环本行'));
    await tester.pumpAndSettle();
    expect(toggled, isFalse);
  });

  group('the playback group', () {
    testWidgets('another song: offer to start, no progress bar', (
      tester,
    ) async {
      await pumpAt(tester, buildToolbar(), const Size(1280, 900));

      expect(find.text('尚未开始试听'), findsOneWidget);
      expect(find.byTooltip('继续试听'), findsOneWidget);
      expect(find.byType(SeekableProgressBar), findsNothing);

      await tester.tap(find.byTooltip('继续试听'));
      expect(calls, ['play']);
    });

    testWidgets('a play state of another song is not ours to pause', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildToolbar(player: _player(playing: true)),
        const Size(1280, 900),
      );

      // The player is busy with a different song, so the button resumes
      // this project instead of offering to pause someone else's.
      expect(find.byTooltip('继续试听'), findsOneWidget);
      expect(find.byTooltip('暂停试听'), findsNothing);
    });

    testWidgets('our song playing: pause, and the progress bar shows', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildToolbar(player: _player(ours: true, playing: true)),
        const Size(1280, 900),
      );

      expect(find.byTooltip('暂停试听'), findsOneWidget);
      expect(find.text('尚未开始试听'), findsNothing);
      expect(find.byType(SeekableProgressBar), findsOneWidget);
    });
  });

  group('the review group', () {
    testWidgets('the follow chip reads and writes the group', (tester) async {
      bool? follow;
      await pumpAt(
        tester,
        buildToolbar(
          followPlayback: false,
          onFollowChanged: (value) => follow = value,
        ),
        const Size(1280, 900),
      );

      final chip = tester.widget<FilterChip>(
        find.ancestor(of: find.text('跟随播放'), matching: find.byType(FilterChip)),
      );
      expect(chip.selected, isFalse);
      expect(find.byIcon(Icons.location_disabled_rounded), findsOneWidget);

      await tester.tap(find.text('跟随播放'));
      await tester.pumpAndSettle();
      expect(follow, isTrue);
    });

    testWidgets('the chip counts the group queue', (tester) async {
      await pumpAt(
        tester,
        buildToolbar(review: _queue(needsReview: 2)),
        const Size(1280, 900),
      );

      expect(find.text('建议复核 2'), findsOneWidget);
    });
  });

  testWidgets('宽屏工具栏把一键校对放在校对菜单旁边', (tester) async {
    await pumpAt(
      tester,
      buildToolbar(
        proofread: LyricProofreadActions(
          onAutoProofread: () => calls.add('auto'),
          onSmartProofread: _noop,
        ),
      ),
      const Size(1280, 900),
    );

    expect(find.text(AutoProofreadStrings.actionTitle), findsOneWidget);
    await tester.tap(find.text(AutoProofreadStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(calls, ['auto']);
  });

  testWidgets('校对进行中按钮变为不可点的「校对中…」', (tester) async {
    await pumpAt(
      tester,
      buildToolbar(
        proofread: const LyricProofreadActions(
          autoProofreadRunning: true,
          onSmartProofread: _noop,
        ),
      ),
      const Size(1280, 900),
    );

    expect(find.text(AutoProofreadStrings.runningLabel), findsOneWidget);
    expect(find.text(AutoProofreadStrings.actionTitle), findsNothing);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(AutoProofreadStrings.runningLabel),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('校对分组原样交给菜单：批量工具按种类回调', (tester) async {
    final tools = <LyricBatchTextTool>[];
    await pumpAt(
      tester,
      buildToolbar(
        proofread: LyricProofreadActions(
          onReferenceAlignment: () => calls.add('alignment'),
          onBatchTextTool: tools.add,
        ),
      ),
      // Tall enough for the whole menu, so every entry can be tapped.
      const Size(1280, 2400),
    );

    await tester.tap(find.text('校对'));
    await tester.pumpAndSettle();
    // Only the tools the group offers are listed; 智能校对 is not among them.
    expect(find.text('智能校对'), findsNothing);
    await tester.tap(find.text(LyricTapSyncStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(tools, [LyricBatchTextTool.tapSync]);

    await tester.tap(find.text('校对'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴参考歌词校对'));
    await tester.pumpAndSettle();
    expect(calls, ['alignment']);
  });

  testWidgets('没有可用的校对工具时不显示校对菜单', (tester) async {
    await pumpAt(
      tester,
      buildToolbar(proofread: LyricProofreadActions.none),
      const Size(1280, 900),
    );

    expect(find.text('校对'), findsNothing);
    // play, filter, follow, offset
    expect(tester.widgetList(_interactiveControls).length, 4);
  });

  testWidgets('更多的入口按可用性出现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LyricEditorOverflowMenu(
                onUndo: null,
                onRedo: null,
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

    expect(find.text('LRC、逐字 LRC、ASS 卡拉 OK、SRT、WebVTT 或纯文本'), findsOneWidget);
    await tester.tap(find.text('导出歌词'));
    await tester.pumpAndSettle();
    expect(calls, contains('export'));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整播放器'));
    await tester.pumpAndSettle();
    expect(calls, contains('player'));
  });

  testWidgets('撤销与重做在没有历史时置灰，并说明快捷键', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LyricEditorOverflowMenu(
                canExport: false,
                onExport: () {},
                onInsertAtPlayback: null,
                onOpenPlayer: null,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    MenuItemButton entryFor(String label) => tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(MenuItemButton),
      ),
    );

    expect(entryFor('撤销').onPressed, isNull);
    expect(entryFor('重做').onPressed, isNull);
    expect(find.text('没有可撤销的修改'), findsOneWidget);
    expect(find.text('没有可重做的修改'), findsOneWidget);
  });

  testWidgets('撤销菜单项说明这一步会撤掉什么', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LyricEditorOverflowMenu(
                onUndo: () => calls.add('undo'),
                onRedo: () => calls.add('redo'),
                undoLabel: '修改第 3 行',
                redoLabel: '删除第 2 行',
                canExport: false,
                onExport: () {},
                onInsertAtPlayback: null,
                onOpenPlayer: null,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    expect(find.text('修改第 3 行（Ctrl/Cmd+Z）'), findsOneWidget);
    expect(find.text('删除第 2 行（Ctrl/Cmd+Shift+Z）'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(calls, contains('undo'));
  });
}
