import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_asr_loop_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_export_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_strip.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine _line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

LyricDocument _doc(List<LyricLine> lines) =>
    LyricDocument(language: 'zh', lines: lines);

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _timed(String text) => LyricLine(
  text: text,
  startTime: _ms(1000),
  endTime: _ms(6000),
  words: [
    LyricWordTiming(text: '我', start: _ms(1000), end: _ms(1400)),
    LyricWordTiming(text: '爱', start: _ms(1400), end: _ms(1800)),
    LyricWordTiming(text: '你', start: _ms(2000), end: _ms(6000)),
  ],
);

Future<T? Function()> _openDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open,
) async {
  T? result;
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  group('LyricAsrLoopDialog', () {
    testWidgets('selects clear loops, lists weaker ones and applies', (
      tester,
    ) async {
      final previewed = <int>[];
      final result = await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricAsrLoopDialog(
          context,
          document: _doc([
            _line('开头', 0, 1000, id: 'a'),
            _line('我爱你我爱你我爱你我爱你我爱你我爱你', 1000, 3000, id: 'b'),
            _line('爱你爱你爱你爱你', 3000, 4000, id: 'c'),
            for (var i = 0; i < 6; i++)
              _line('谢谢', 5000 + i * 1000, 5800 + i * 1000, id: 'd$i'),
          ]),
          protectedIndices: const {},
          onPreviewLine: previewed.add,
        ),
      );
      expect(find.text('行内循环 2 处，连续重复行 1 组；默认勾选 2 项明显的循环。'), findsOneWidget);
      expect(find.text('删减 1 行，删除 4 行'), findsOneWidget);
      expect(find.textContaining('可能是歌词本身的重复'), findsOneWidget);

      await tester.tap(find.byTooltip('试听第 2 行'));
      expect(previewed, [1]);

      await tester.tap(find.byKey(const ValueKey('asr_loop_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(edit.document.lines.map((l) => l.text), [
        '开头',
        '我爱你我爱你',
        '爱你爱你爱你爱你',
        '谢谢',
        '谢谢',
      ]);
      expect(edit.selectedLineIndex, 1);
      expect(edit.message, '已删减 1 行内的重复，已删除 4 行重复行（未写入磁盘）');
      expect(edit.label, LyricAsrLoopStrings.actionTitle);
    });

    testWidgets('hand-edited loops are listed without a checkbox', (
      tester,
    ) async {
      await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricAsrLoopDialog(
          context,
          document: _doc([_line('啊啊啊啊啊啊啊啊啊啊啊啊', 0, 4000, id: 'a')]),
          protectedIndices: const {0},
        ),
      );
      expect(find.textContaining('手动编辑过，不修改'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('没有可自动处理的循环'), findsOneWidget);
    });

    testWidgets('a couplet cycling over an interlude is cut to two passes', (
      tester,
    ) async {
      final result = await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricAsrLoopDialog(
          context,
          document: _doc([
            _line('第一段在这里', 0, 2000, id: 'v'),
            for (var i = 0; i < 6; i++) ...[
              _line('雨夜的路上', 3000 + i * 4000, 4800 + i * 4000, id: 'x$i'),
              _line('风一直在吹', 5000 + i * 4000, 6800 + i * 4000, id: 'y$i'),
            ],
          ]),
          protectedIndices: const {},
        ),
      );
      expect(find.textContaining('2 行一组连续循环 6 遍，删除 8 行'), findsOneWidget);
      expect(find.text('删除 8 行'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('asr_loop_confirm')));
      await tester.pumpAndSettle();
      expect(result()!.document.lines.map((l) => l.id), [
        'v',
        'x0',
        'y0',
        'x1',
        'y1',
      ]);
    });

    testWidgets('a clean draft has nothing to do', (tester) async {
      await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricAsrLoopDialog(
          context,
          document: _doc([_line('春风吹过山岗', 0, 2000)]),
          protectedIndices: const {},
        ),
      );
      expect(find.text('没有发现识别循环。'), findsOneWidget);
    });
  });

  testWidgets('the proofread menu offers the loop check', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(onAsrLoopCheck: () => fired++),
          ),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LyricAsrLoopStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  test('the summary card hints at loops right after caption rows', () {
    final hints = LyricRecognitionSummaryCard.healthHints(
      const LyricDraftHealth(
        captionRows: 1,
        repetitionGroups: 0,
        longLines: 1,
        fragments: 0,
        loopRows: 3,
      ),
    );
    expect(hints.map((h) => h.tool), [
      LyricBatchTextTool.textCleanup,
      LyricBatchTextTool.asrLoopCheck,
      LyricBatchTextTool.lineStructure,
    ]);
    expect(hints[1].label, '识别循环 3 行');
  });

  group('LyricWordTimingStrip', () {
    Future<void> pumpStrip(WidgetTester tester, LyricLine line) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LyricWordTimingStrip(line: line)),
          ),
        );

    testWidgets('shows every word with its start and marks long ones', (
      tester,
    ) async {
      await pumpStrip(tester, _timed('我爱你'));
      expect(find.byKey(const ValueKey('word_timing_strip')), findsOneWidget);
      expect(find.text('我'), findsOneWidget);
      expect(find.text('0:02.0'), findsOneWidget);
      expect(find.text('3 个词，1 个拖长超过 2.5 秒'), findsOneWidget);
    });

    testWidgets('says when the text no longer matches', (tester) async {
      await pumpStrip(tester, _timed('我爱你们'));
      expect(find.byKey(const ValueKey('word_timing_stale')), findsOneWidget);
      expect(find.text(LyricWordTimingStrip.staleNote), findsOneWidget);
    });

    testWidgets('rows without word timing show nothing', (tester) async {
      await pumpStrip(tester, _line('我爱你', 0, 1000));
      expect(find.byType(Wrap), findsNothing);
      expect(find.text('逐字时间'), findsNothing);
    });

    test('clock is compact', () {
      expect(LyricWordTimingStrip.clock(_ms(83450)), '1:23.4');
      expect(LyricWordTimingStrip.clock(_ms(2000)), '0:02.0');
    });
  });

  testWidgets('the export dialog says which rows use real word timing', (
    tester,
  ) async {
    await _openDialog<LyricExportRequest>(
      tester,
      (context) => showLyricExportDialog(
        context,
        document: _doc([_timed('我爱你'), _line('春风', 7000, 8000)]),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('lyric_export_format_karaokeLrc')),
    );
    await tester.tap(
      find.byKey(const ValueKey('lyric_export_format_karaokeLrc')),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 行使用识别或逐字打点得到的真实逐字时间，其余行按字数比例估算。'), findsOneWidget);
    expect(find.textContaining('逐字时间按每行'), findsNothing);
  });
}
