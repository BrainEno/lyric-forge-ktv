import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_missed_repeat_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(
  String text,
  int startMs,
  int endMs, {
  String? id,
  List<LyricWordTiming> words = const [],
}) => LyricLine(
  text: text,
  startTime: _ms(startMs),
  endTime: _ms(endMs),
  id: id,
  words: words,
);

LyricWordTiming _w(String text, int startMs, int endMs) =>
    LyricWordTiming(text: text, start: _ms(startMs), end: _ms(endMs));

/// A stretched intro word on row 1 and a chant before a silent ending on
/// row 3.
LyricDocument _draft() => LyricDocument(
  language: 'en',
  lines: [
    _line(
      'the night is young',
      0,
      26000,
      id: 'a',
      words: [
        _w('the', 0, 25600),
        _w('night', 25600, 25800),
        _w('is', 25800, 25900),
        _w('young', 25900, 26000),
      ],
    ),
    _line('and I keep the light', 27000, 31000, id: 'b'),
    _line('whoa oh oh oh', 80000, 83000, id: 'c'),
  ],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<LyricBatchTextEdit? Function()> _open(
  WidgetTester tester, {
  required LyricDocument document,
  Duration? audioDuration,
  Set<int> protectedIndices = const {},
  ValueChanged<int>? onPreviewLine,
  LyricSpanPreview? onPreviewSpan,
}) async {
  LyricBatchTextEdit? result;
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showLyricMissedRepeatDialog(
                context,
                document: document,
                protectedIndices: protectedIndices,
                audioDuration: audioDuration,
                onPreviewLine: onPreviewLine,
                onPreviewSpan: onPreviewSpan,
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
  return () => result;
}

void main() {
  testWidgets('lists every kind, trims by default and auditions spans', (
    tester,
  ) async {
    final rows = <int>[];
    final spans = <(int, Duration, Duration)>[];
    final result = await _open(
      tester,
      document: _draft(),
      audioDuration: _ms(120000),
      onPreviewLine: rows.add,
      onPreviewSpan: (index, start, end) => spans.add((index, start, end)),
    );

    expect(find.text('字被拉长 1 处，和声后长空白 1 处；默认勾选 1 项。'), findsOneWidget);
    expect(find.text('第 3 行 · 这里可能漏了重复的和声'), findsOneWidget);
    expect(find.textContaining('建议从 0:24.8 开始'), findsOneWidget);
    expect(find.textContaining('插入 8 行（最多 8 行）'), findsOneWidget);
    expect(find.text('修正 1 处拉长'), findsOneWidget);

    await _tap(tester, find.byTooltip('试听第 3 行之后的空白'));
    expect(spans.single, (2, _ms(83000), _ms(120000)));
    await _tap(tester, find.byTooltip('试听第 1 行'));
    expect(rows, [0]);

    await tester.tap(find.byKey(const ValueKey('missed_repeat_confirm')));
    await tester.pumpAndSettle();
    final edit = result()!;
    expect(edit.label, LyricMissedRepeatStrings.actionTitle);
    expect(edit.message, '已修正 1 处被拉长的字（未写入磁盘）');
    expect(edit.selectedLineIndex, 0);
    expect(edit.document.lines.first.startTime, _ms(24800));
    expect(edit.document.lines, hasLength(3));
  });

  testWidgets('choosing how many copies ticks the gap and inserts them', (
    tester,
  ) async {
    final result = await _open(
      tester,
      document: _draft(),
      audioDuration: _ms(120000),
    );

    // Untick the trim, then ask for 7 of the 8 copies.
    await _tap(tester, find.byType(Checkbox).first);
    expect(find.text('请选择要处理的项'), findsOneWidget);
    await _tap(tester, find.byTooltip('少插一行'));
    expect(find.textContaining('插入 7 行（最多 8 行）'), findsOneWidget);
    expect(find.text('插入 7 行'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('missed_repeat_confirm')));
    await tester.pumpAndSettle();
    final edit = result()!;
    expect(edit.message, '已插入 7 行重复和声（未写入磁盘）');
    expect(edit.document.lines, hasLength(10));
    expect(edit.document.lines.first.startTime, Duration.zero);
    expect(edit.document.lines[3].text, 'whoa oh oh oh');
    expect(edit.document.lines[3].startTime, _ms(84000));
    expect(edit.selectedLineIndex, 2);
  });

  testWidgets('without audio the ending is not judged and no span plays', (
    tester,
  ) async {
    await _open(tester, document: _draft(), protectedIndices: {0});
    expect(find.text('字被拉长 1 处；默认勾选 0 项。'), findsOneWidget);
    expect(find.text('本工程没有音频时长，最后一行之后的空白无法检查。'), findsOneWidget);
    expect(find.textContaining('手动编辑过，不修改'), findsOneWidget);
    expect(find.text('没有可自动处理的项'), findsOneWidget);
    expect(find.byIcon(Icons.hearing_rounded), findsNothing);
  });

  testWidgets('a clean draft has nothing to report', (tester) async {
    await _open(
      tester,
      document: LyricDocument(
        language: 'en',
        lines: [_line('I walk the empty street', 0, 3000)],
      ),
      audioDuration: _ms(4000),
    );
    expect(find.text('没有发现可能漏唱的和声。'), findsOneWidget);
  });

  testWidgets('the proofread menu offers the check', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(onMissedRepeatCheck: () => fired++),
          ),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    expect(find.text(LyricMissedRepeatStrings.actionDetail), findsOneWidget);
    await tester.tap(find.text(LyricMissedRepeatStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  test('the summary card hints at missed repeats before word timing', () {
    final hints = LyricRecognitionSummaryCard.healthHints(
      const LyricDraftHealth(
        captionRows: 0,
        repetitionGroups: 0,
        longLines: 0,
        fragments: 0,
        missedRepeatSpots: 2,
        staleWordRows: 1,
      ),
    );
    expect(hints.map((hint) => hint.tool), [
      LyricBatchTextTool.missedRepeatCheck,
      LyricBatchTextTool.wordTimingCheck,
    ]);
    expect(hints.first.label, '可能漏唱的和声 2 处');
  });
}
