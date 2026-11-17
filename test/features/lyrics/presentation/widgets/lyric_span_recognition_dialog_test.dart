import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_span_recognition_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricDocument _draft({Duration? offset}) => LyricDocument(
  language: 'en',
  globalOffset: offset,
  lines: [
    _line('open the door', 10000, 13000, id: 'a'),
    _line('garbled garbled', 14000, 18000, id: 'b'),
    _line('close the door', 22000, 25000, id: 'c'),
  ],
);

class _Recognizer implements LyricSpanRecognizer {
  final recognized =
      <({Duration start, Duration end, LyricSpanEngine engine})>[];
  final aligned = <({Duration start, Duration end, String text})>[];
  List<LyricLine> lines = const [];
  List<ForcedAlignedSpan> spans = const [];
  Object? failure;
  Completer<void>? gate;
  int cancels = 0;

  @override
  Future<LyricRecognizedSpan> recognize({
    required String projectId,
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
  }) async {
    recognized.add((start: start, end: end, engine: engine));
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return LyricRecognizedSpan(
      lines: lines,
      engineLabel: engine == LyricSpanEngine.qwen
          ? 'Qwen3-ASR 1.7B'
          : 'Whisper large-v3',
      language: 'en',
    );
  }

  @override
  Future<List<ForcedAlignedSpan>> align({
    required String projectId,
    required Duration start,
    required Duration end,
    required String text,
    required String language,
  }) async {
    aligned.add((start: start, end: end, text: text));
    if (failure != null) throw failure!;
    return spans;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    gate?.complete();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<LyricBatchTextEdit? Function()> _open(
  WidgetTester tester, {
  required LyricDocument document,
  required _Recognizer recognizer,
  int? selectedIndex = 1,
  Set<int> protectedIndices = const {},
  Duration? audioDuration,
}) async {
  LyricBatchTextEdit? result;
  tester.view.physicalSize = const Size(1200, 2000);
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
                  result = await showLyricSpanRecognitionDialog(
                    context,
                    document: document,
                    projectId: 'project',
                    recognizer: recognizer,
                    selectedIndex: selectedIndex,
                    protectedIndices: protectedIndices,
                    audioDuration: audioDuration,
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
  testWidgets('recognises the selected row again and replaces it', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..lines = [
        _line('the real line', 14100, 16000),
        _line('and a missed one', 16200, 19500),
      ];
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );

    expect(find.text(LyricSpanRecognitionStrings.actionTitle), findsOneWidget);
    expect(
      find.textContaining('处理范围 0:13.5–0:18.5'),
      findsOneWidget,
      reason: 'half a second of context on both sides',
    );
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();

    expect(recognizer.recognized.single.engine, LyricSpanEngine.qwen);
    expect(recognizer.recognized.single.start, _ms(13500));
    expect(recognizer.recognized.single.end, _ms(18500));
    expect(find.textContaining('Qwen3-ASR 1.7B：1 行 → 2 行'), findsOneWidget);
    expect(find.text('the real line'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('span_recognition_confirm')));
    await tester.pumpAndSettle();
    final edit = result()!;
    expect(edit.document.lines.map((line) => line.text), [
      'open the door',
      'the real line',
      'and a missed one',
      'close the door',
    ]);
    // Clipped to the window.
    expect(edit.document.lines[2].endTime, _ms(18500));
    expect(edit.selectedLineIndex, 1);
    expect(edit.message, contains('未写入磁盘'));
  });

  testWidgets('maps the stretch through the global offset', (tester) async {
    final recognizer = _Recognizer()
      ..lines = [_line('shifted line', 14600, 17500)];
    final result = await _open(
      tester,
      document: _draft(offset: _ms(500)),
      recognizer: recognizer,
    );
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    expect(recognizer.recognized.single.start, _ms(14000));
    expect(recognizer.recognized.single.end, _ms(19000));

    await _tap(tester, find.byKey(const ValueKey('span_recognition_confirm')));
    await tester.pumpAndSettle();
    final line = result()!.document.lines[1];
    expect(line.text, 'shifted line');
    expect(line.startTime, _ms(14100));
    expect(line.endTime, _ms(17000));
  });

  testWidgets('extends the range and reaches to the next row', (tester) async {
    final recognizer = _Recognizer()
      ..lines = [_line('two rows at once', 10000, 20000)];
    await _open(tester, document: _draft(), recognizer: recognizer);

    await _tap(tester, find.byTooltip('从第上一行'));
    expect(find.textContaining('2 行）'), findsOneWidget);

    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('span_tail')),
        matching: find.byType(DropdownButton<LyricSpanReach>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('到下一行').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('–0:22.0'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(const ValueKey('span_mode_recognizeWhisper')),
    );
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    expect(recognizer.recognized.single.engine, LyricSpanEngine.whisper);
    expect(recognizer.recognized.single.end, _ms(22000));
  });

  testWidgets('can replace only the text and keep the timing', (tester) async {
    final recognizer = _Recognizer()
      ..lines = [_line('fixed words', 14300, 17000)];
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('span_text_only')));
    expect(find.text('只替换 1 行的文字'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('span_recognition_confirm')));
    await tester.pumpAndSettle();
    final line = result()!.document.lines[1];
    expect(line.text, 'fixed words');
    expect(line.startTime, _ms(14000));
    expect(line.endTime, _ms(18000));
    expect(line.id, 'b');
  });

  testWidgets('re-aligns the existing text', (tester) async {
    final recognizer = _Recognizer()
      ..spans = [
        ForcedAlignedSpan(text: 'garbled', start: _ms(14200), end: _ms(15000)),
        ForcedAlignedSpan(text: 'garbled', start: _ms(15100), end: _ms(17200)),
      ];
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    await _tap(tester, find.byKey(const ValueKey('span_mode_realign')));
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    expect(recognizer.aligned.single.text, 'garbled garbled');
    expect(find.textContaining('对齐了 1 行'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('span_recognition_confirm')));
    await tester.pumpAndSettle();
    final line = result()!.document.lines[1];
    expect(line.text, 'garbled garbled');
    expect(line.startTime, _ms(14200));
    expect(line.endTime, _ms(17200));
    expect(line.words, hasLength(2));
  });

  testWidgets('a mismatching alignment changes nothing', (tester) async {
    final recognizer = _Recognizer()
      ..spans = [
        ForcedAlignedSpan(text: 'other', start: _ms(14200), end: _ms(15000)),
      ];
    await _open(tester, document: _draft(), recognizer: recognizer);
    await _tap(tester, find.byKey(const ValueKey('span_mode_realign')));
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('对不上'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('span_recognition_confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('shows recogniser failures', (tester) async {
    final recognizer = _Recognizer()
      ..failure = const LyricSpanRecognitionException('识别资源正在被其他任务使用，请稍后重试');
    await _open(tester, document: _draft(), recognizer: recognizer);
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await tester.pumpAndSettle();
    expect(find.text('识别资源正在被其他任务使用，请稍后重试'), findsOneWidget);
  });

  testWidgets('warns about hand-edited rows in the range', (tester) async {
    await _open(
      tester,
      document: _draft(),
      recognizer: _Recognizer(),
      protectedIndices: {1},
    );
    expect(find.textContaining('1 行手动编辑过'), findsOneWidget);
  });

  testWidgets('stopping or closing cancels a running request', (tester) async {
    final recognizer = _Recognizer()..gate = Completer<void>();
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    expect(find.text('正在重新识别…'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('span_cancel_run')));
    await tester.pumpAndSettle();
    expect(recognizer.cancels, 1);
    expect(find.text('已取消。'), findsOneWidget);

    recognizer.gate = Completer<void>();
    await _tap(tester, find.byKey(const ValueKey('span_run')));
    await _tap(tester, find.text('取消'));
    await tester.pumpAndSettle();
    expect(recognizer.cancels, 2);
    expect(result(), isNull);
  });

  testWidgets('the proofread menu offers it', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(onSpanRecognition: () => fired++),
          ),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    expect(find.text(LyricSpanRecognitionStrings.actionDetail), findsOneWidget);
    await tester.tap(find.text(LyricSpanRecognitionStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });
}
