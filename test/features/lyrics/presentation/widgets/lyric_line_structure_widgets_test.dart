import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_inspector_pane.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_structure_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
const _longLine = '夜空中最亮的星能否听清 那仰望的人心底的孤独和叹息';

LyricLine _line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

void main() {
  group('LineInspector split and merge', () {
    Future<List<Object?>> pumpInspector(
      WidgetTester tester, {
      bool withMerge = true,
    }) async {
      final calls = <Object?>[];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LineInspector(
              index: 0,
              line: _line('我爱你你爱我', 0, 6000, id: 'a'),
              fallbackCandidate: null,
              isReviewed: false,
              onReviewDecision: null,
              isCurrentPlaybackLine: false,
              isPlaying: false,
              onUpdate: (_) {},
              onDelete: () {},
              onSplit: (offset) => calls.add(('split', offset)),
              onMergeWithNext: withMerge ? () => calls.add('merge') : null,
              onPreview: () {},
            ),
          ),
        ),
      );
      return calls;
    }

    testWidgets('splits at the natural break when the cursor is not inside', (
      tester,
    ) async {
      final calls = await pumpInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector_split_line')));
      expect(calls, [('split', null)]);
    });

    testWidgets('splits at the text cursor', (tester) async {
      final calls = await pumpInspector(tester);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '我爱你你爱我',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('inspector_split_line')));
      expect(calls, [('split', 3)]);
    });

    testWidgets('Ctrl+Enter in the text splits at the cursor', (tester) async {
      final calls = await pumpInspector(tester);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '我爱你你爱我',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(calls, [('split', 2)]);
    });

    testWidgets('merge runs the callback and is disabled on the last row', (
      tester,
    ) async {
      final calls = await pumpInspector(tester);
      await tester.tap(find.byKey(const ValueKey('inspector_merge_next')));
      expect(calls, ['merge']);

      await pumpInspector(tester, withMerge: false);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('inspector_merge_next')),
      );
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('the list context menu offers split and merge', (tester) async {
    final calls = <Object?>[];
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _line('我爱你，你爱我', 0, 3000, id: 'a'),
        _line('下一行', 3000, 6000, id: 'b'),
      ],
    );
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricListPane(
            document: document,
            visibleIndices: const [0, 1],
            reviewPriorityByIndex: const {},
            filter: LyricReviewFilter.all,
            activeAuditionLineIndex: null,
            auditionPlaying: false,
            selectedIndex: 0,
            currentPlaybackLine: null,
            followPlayback: false,
            focusRequestId: 0,
            focusLineIndex: null,
            fallbackCandidateFor: (_) => null,
            onPreviewLine: null,
            onInsertedLineFocus: (_) {},
            onSelectLine: (_) {},
            onUpdateLine: (_, _) {},
            onDeleteLine: (_) {},
            onSplitLine: (index, offset) => calls.add(('split', index, offset)),
            onMergeLineWithNext: (index) => calls.add(('merge', index)),
          ),
        ),
      ),
    );

    Future<void> openMenu(String rowLabel) async {
      await tester.tap(find.text(rowLabel), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    await openMenu('第 1 行');
    await tester.tap(find.text('从中间断点拆分为两行'));
    await tester.pumpAndSettle();
    expect(calls.last, ('split', 0, null));

    await openMenu('第 1 行');
    await tester.tap(find.text('与下一行合并'));
    await tester.pumpAndSettle();
    expect(calls.last, ('merge', 0));

    // The last row has nothing to merge with.
    await openMenu('第 2 行');
    expect(find.text('与下一行合并'), findsNothing);
    expect(find.text('从中间断点拆分为两行'), findsOneWidget);
  });

  group('LyricStructureDialog', () {
    late LyricBatchTextEdit? result;

    Future<void> open(WidgetTester tester, LyricDocument document) async {
      result = null;
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async =>
                      result = await showLyricStructureDialog(
                        context,
                        document: document,
                        protectedIndices: const {},
                      ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final mixed = LyricDocument(
      language: 'zh',
      lines: [
        _line(_longLine, 0, 6000, id: 'long'),
        _line('夜空中最亮的星', 6000, 9000, id: 'a'),
        _line('啊', 9100, 9500, id: 'frag'),
        _line('一二三四五六七八九十一二三四五六七八九十一', 12000, 20000, id: 'run'),
      ],
    );

    testWidgets('pre-selects confident suggestions and applies them', (
      tester,
    ) async {
      await open(tester, mixed);
      expect(find.textContaining('发现 2 行过长、1 处碎片行'), findsOneWidget);
      // The break-less run is listed but must be opted into.
      expect(find.text('拆分 1 行、合并 1 处'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('structure_confirm')));
      await tester.pumpAndSettle();

      final edit = result!;
      expect(edit.label, LyricStructureStrings.actionTitle);
      expect(edit.document.lines.map((l) => l.text), [
        '夜空中最亮的星能否听清',
        '那仰望的人心底的孤独和叹息',
        '夜空中最亮的星啊',
        '一二三四五六七八九十一二三四五六七八九十一',
      ]);
      expect(edit.selectedLineIndex, 0);
      expect(edit.message, contains('未写入磁盘'));
    });

    testWidgets('select all includes the guessed split', (tester) async {
      await open(tester, mixed);
      await tester.tap(find.byKey(const ValueKey('structure_toggle_all')));
      await tester.pumpAndSettle();
      expect(find.text('拆分 2 行、合并 1 处'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('structure_toggle_all')));
      await tester.pumpAndSettle();
      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('structure_confirm')),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('a clean document has nothing to apply', (tester) async {
      await open(
        tester,
        LyricDocument(
          language: 'zh',
          lines: [_line('夜空中最亮的星', 0, 3000), _line('能否听清', 4000, 6000)],
        ),
      );
      expect(find.text('没有发现过长或被切碎的行。'), findsOneWidget);
      expect(find.text('无需整理'), findsOneWidget);
    });
  });

  group('recognition summary health hints', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _line('夜空中最亮的星', 0, 3000),
        _line('[音乐]', 4000, 7000),
        _line(_longLine, 8000, 14000),
      ],
      metadata: const {'primaryEngine': 'qwen3-asr-1.7b'},
    );

    Future<List<LyricBatchTextTool>> pump(
      WidgetTester tester, {
      LyricDraftHealth? health,
    }) async {
      final opened = <LyricBatchTextTool>[];
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricRecognitionSummaryCard(
                  summary: RecognitionReviewSummary.fromDocument(
                    document,
                    LyricReviewQueue.build(document),
                  ),
                  onStartReview: null,
                  health: health,
                  onOpenBatchTool: opened.add,
                ),
              ],
            ),
          ),
        ),
      );
      return opened;
    }

    testWidgets('each hint opens the tool that fixes it', (tester) async {
      final opened = await pump(
        tester,
        health: const LyricDraftHealthService().analyze(document),
      );
      expect(find.text('字幕水印/标注 1 行'), findsOneWidget);
      expect(find.text('过长 1 行'), findsOneWidget);
      expect(find.textContaining('重复句写法不一'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('lyric_health_textCleanup')));
      await tester.tap(
        find.byKey(const ValueKey('lyric_health_lineStructure')),
      );
      expect(opened, [
        LyricBatchTextTool.textCleanup,
        LyricBatchTextTool.lineStructure,
      ]);
    });

    testWidgets('a clean draft or a missing health shows no hints', (
      tester,
    ) async {
      await pump(tester, health: LyricDraftHealth.clean);
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_health')),
        findsNothing,
      );
      await pump(tester);
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_health')),
        findsNothing,
      );
    });
  });

  testWidgets('the proofreading menu offers the line-structure tool', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(onLineStructure: () => opened++),
          ),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    expect(find.text(LyricStructureStrings.actionDetail), findsOneWidget);
    await tester.tap(find.text(LyricStructureStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
