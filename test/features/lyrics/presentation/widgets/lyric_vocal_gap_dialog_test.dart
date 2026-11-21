import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_vocal_gap_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricVocalCheckSpan _span(int startMs, int endMs) =>
    LyricVocalCheckSpan(_ms(startMs), _ms(endMs));

final _spans = [_span(20000, 24000), _span(40000, 43000)];

LyricDocument _draft({
  Duration? offset,
  List<LyricVocalCheckSpan>? spans,
  List<LyricLine>? lines,
}) => LyricDocument(
  language: 'en',
  globalOffset: offset,
  lines:
      lines ??
      [
        _line('first line', 10000, 14000, id: 'a'),
        _line('second line', 30000, 34000, id: 'b'),
        _line('third line', 50000, 54000, id: 'c'),
      ],
  metadata: {
    LyricVocalCheckRecord.metadataKey: LyricVocalCheckRecord(
      uncoveredSpans: spans ?? _spans,
    ).toJson(),
  },
);

class _Recognizer implements LyricSpanRecognizer {
  final calls = <({Duration start, Duration end, LyricSpanEngine engine})>[];
  List<LyricLine> lines = const [];
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
    calls.add((start: start, end: end, engine: engine));
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
  }) async => const [];

  @override
  Future<void> cancel() async {
    cancels++;
    final pending = gate;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _frames(tester);
}

final _previews = <({int index, Duration start, Duration end})>[];

Future<LyricBatchTextEdit? Function()> _open(
  WidgetTester tester, {
  required LyricDocument document,
  required _Recognizer recognizer,
  List<LyricVocalCheckSpan>? spans,
  LyricVocalCheckSpan? initialSpan,
  Duration? audioDuration,
  bool preview = false,
}) async {
  LyricBatchTextEdit? result;
  _previews.clear();
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
              onPressed: () async => result = await showLyricVocalGapDialog(
                context,
                document: document,
                spans: spans ?? _spans,
                projectId: 'project',
                recognizer: recognizer,
                initialSpan: initialSpan,
                audioDuration: audioDuration,
                onPreviewSpan: preview
                    ? (index, start, end) => _previews.add((
                        index: index,
                        start: start,
                        end: end,
                      ))
                    : null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _frames(tester);
  return () => result;
}

FilledButton _confirm(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('vocal_gap_confirm')),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  testWidgets('recognises the first stretch as soon as it opens', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..lines = [_line('found in the gap', 20100, 23800)];
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );

    expect(find.text(LyricVocalCheckStrings.gapTitle), findsOneWidget);
    expect(recognizer.calls, hasLength(1));
    expect(recognizer.calls.single.engine, LyricSpanEngine.qwen);
    expect(recognizer.calls.single.start, _ms(19700));
    expect(recognizer.calls.single.end, _ms(24300));
    expect(_text(tester, 'vocal_gap_position'), contains('第 1 / 2 处'));
    expect(_text(tester, 'vocal_gap_window'), contains('插入在第 2 行之前'));
    expect(_text(tester, 'vocal_gap_result'), contains('Qwen3-ASR 1.7B'));
    expect(find.textContaining('found in the gap'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNotNull);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_confirm')));
    final edit = result()!;
    expect([for (final line in edit.document.lines) line.text], [
      'first line',
      'found in the gap',
      'second line',
      'third line',
    ]);
    expect(edit.selectedLineIndex, 1);
    expect(edit.label, LyricVocalCheckStrings.gapTitle);
    expect(edit.message, contains('插入 1 行'));
    expect(edit.message, contains('未写入磁盘'));
    expect(edit.document.lines[1].id, isNotNull);
    expect(edit.document.lines.first.id, 'a');
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(record.openSpans(edit.document), [_spans.last]);
  });

  testWidgets('starts at the stretch the card asked for', (tester) async {
    final recognizer = _Recognizer()..lines = [_line('late', 40000, 42000)];
    await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      initialSpan: _spans.last,
    );
    expect(_text(tester, 'vocal_gap_position'), contains('第 2 / 2 处'));
    expect(recognizer.calls.single.start, _ms(39700));
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('vocal_gap_next')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('an unknown initial stretch falls back to the first', (
    tester,
  ) async {
    final recognizer = _Recognizer();
    await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      initialSpan: _span(1, 2),
    );
    expect(_text(tester, 'vocal_gap_position'), contains('第 1 / 2 处'));
  });

  testWidgets('moving to another stretch recognises it right away', (
    tester,
  ) async {
    final recognizer = _Recognizer()..lines = [_line('words', 20000, 22000)];
    await _open(tester, document: _draft(), recognizer: recognizer);
    final previous = tester.widget<IconButton>(
      find.byKey(const ValueKey('vocal_gap_previous')),
    );
    expect(previous.onPressed, isNull);

    recognizer.lines = [_line('other words', 40100, 42500)];
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_next')));
    expect(recognizer.calls, hasLength(2));
    expect(recognizer.calls.last.start, _ms(39700));
    expect(recognizer.calls.last.end, _ms(43300));
    expect(find.textContaining('other words'), findsOneWidget);
    expect(_text(tester, 'vocal_gap_window'), contains('插入在第 3 行之前'));

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_previous')));
    expect(recognizer.calls, hasLength(3));
    expect(recognizer.calls.last.start, _ms(19700));
  });

  testWidgets('switching the engine recognises again', (tester) async {
    final recognizer = _Recognizer()..lines = [_line('words', 20000, 22000)];
    await _open(tester, document: _draft(), recognizer: recognizer);
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_engine_whisper')));
    expect(recognizer.calls.map((call) => call.engine), [
      LyricSpanEngine.qwen,
      LyricSpanEngine.whisper,
    ]);
    expect(_text(tester, 'vocal_gap_result'), contains('Whisper large-v3'));
    final whisper = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('vocal_gap_engine_whisper')),
    );
    expect(whisper.selected, isTrue);
  });

  testWidgets('nothing recognised says so and offers the dismissal', (
    tester,
  ) async {
    final recognizer = _Recognizer();
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    expect(find.byKey(const ValueKey('vocal_gap_error')), findsOneWidget);
    expect(find.textContaining('没有识别出歌词'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);
    expect(find.text('没有可插入的歌词'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_dismiss')));
    final edit = result()!;
    expect(edit.document.lines, hasLength(3));
    expect(edit.selectedLineIndex, isNull);
    expect(edit.message, contains('没有歌词'));
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(record.uncoveredSpans, [_spans.last]);
    expect(record.dismissedSpans, 1);
  });

  testWidgets('a failure is shown and can be retried', (tester) async {
    final recognizer = _Recognizer()
      ..failure = const LyricSpanRecognitionException('运行时正忙', busy: true);
    await _open(tester, document: _draft(), recognizer: recognizer);
    expect(find.text('运行时正忙'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);

    recognizer
      ..failure = null
      ..lines = [_line('second try', 20000, 22000)];
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_rerun')));
    expect(recognizer.calls, hasLength(2));
    expect(find.text('运行时正忙'), findsNothing);
    expect(find.textContaining('second try'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNotNull);
  });

  testWidgets('stopping cancels the running request', (tester) async {
    final recognizer = _Recognizer()
      ..gate = Completer<void>()
      ..lines = [_line('too late', 20000, 22000)];
    await _open(tester, document: _draft(), recognizer: recognizer);
    expect(find.byKey(const ValueKey('vocal_gap_stop')), findsOneWidget);
    expect(find.text('正在识别…'), findsWidgets);
    expect(_confirm(tester).onPressed, isNull);
    final dismiss = tester.widget<TextButton>(
      find.byKey(const ValueKey('vocal_gap_dismiss')),
    );
    expect(dismiss.onPressed, isNull);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_stop')));
    expect(recognizer.cancels, 1);
    expect(find.text('已停止。'), findsOneWidget);
    // The late answer of the stopped run is ignored.
    expect(find.textContaining('too late'), findsNothing);
    expect(find.byKey(const ValueKey('vocal_gap_rerun')), findsOneWidget);
  });

  testWidgets('a cancelled run reports that it stopped', (tester) async {
    final recognizer = _Recognizer()
      ..failure = const LyricSpanRecognitionException('x', cancelled: true);
    await _open(tester, document: _draft(), recognizer: recognizer);
    expect(find.text('已停止。'), findsOneWidget);
  });

  testWidgets('closing while it runs cancels the request', (tester) async {
    final recognizer = _Recognizer()..gate = Completer<void>();
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    await _tap(tester, find.text('取消'));
    expect(recognizer.cancels, 1);
    expect(result(), isNull);
  });

  testWidgets('a stretch squeezed between rows is not sent', (tester) async {
    final squeezed = _span(14050, 14250);
    final document = _draft(
      spans: [squeezed],
      lines: [_line('one', 10000, 14000), _line('two', 14300, 18000)],
    );
    final recognizer = _Recognizer();
    await _open(
      tester,
      document: document,
      recognizer: recognizer,
      spans: [squeezed],
    );
    expect(recognizer.calls, isEmpty);
    expect(find.textContaining('不到 0.5 秒'), findsOneWidget);
    expect(find.byKey(const ValueKey('vocal_gap_rerun')), findsNothing);
    final whisper = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('vocal_gap_engine_whisper')),
    );
    expect(whisper.onSelected, isNull);
    // Saying there is nothing to sing still works.
    final dismiss = tester.widget<TextButton>(
      find.byKey(const ValueKey('vocal_gap_dismiss')),
    );
    expect(dismiss.onPressed, isNotNull);
  });

  testWidgets('a stretch over ninety seconds is not sent', (tester) async {
    final long = _span(60000, 160000);
    final recognizer = _Recognizer();
    await _open(
      tester,
      document: _draft(spans: [long]),
      recognizer: recognizer,
      spans: [long],
    );
    expect(recognizer.calls, isEmpty);
    expect(find.textContaining('超过 90 秒'), findsOneWidget);
  });

  testWidgets('works on the audio timeline with a global offset', (
    tester,
  ) async {
    // The audio is 500 ms behind the document: a document time t plays at
    // t + 500 ms, and recognised times come back on the audio's timeline.
    final recognizer = _Recognizer()
      ..lines = [
        const LyricLine(
          text: 'shifted words',
          startTime: Duration(milliseconds: 20600),
          endTime: Duration(milliseconds: 23500),
          words: [
            LyricWordTiming(
              text: 'shifted',
              start: Duration(milliseconds: 20600),
              end: Duration(milliseconds: 21500),
            ),
            LyricWordTiming(
              text: 'words',
              start: Duration(milliseconds: 21600),
              end: Duration(milliseconds: 23500),
            ),
          ],
        ),
      ];
    final result = await _open(
      tester,
      document: _draft(offset: _ms(500)),
      recognizer: recognizer,
    );
    expect(recognizer.calls.single.start, _ms(20200));
    expect(recognizer.calls.single.end, _ms(24800));

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_confirm')));
    final inserted = result()!.document.lines[1];
    expect(inserted.startTime, _ms(20100));
    expect(inserted.endTime, _ms(23000));
    expect(inserted.words.first.start, _ms(20100));
    expect(inserted.words.last.end, _ms(23000));
  });

  testWidgets('the window respects the audio length after the last row', (
    tester,
  ) async {
    final tail = _span(56000, 59900);
    final recognizer = _Recognizer();
    await _open(
      tester,
      document: _draft(spans: [tail]),
      recognizer: recognizer,
      spans: [tail],
      audioDuration: _ms(60000),
    );
    expect(recognizer.calls.single.end, _ms(60000));
    expect(_text(tester, 'vocal_gap_window'), contains('插入在第 4 行之前'));
  });

  testWidgets('previews the window anchored on a neighbouring row', (
    tester,
  ) async {
    final tail = _span(56000, 59000);
    final recognizer = _Recognizer();
    await _open(
      tester,
      document: _draft(spans: [_spans.first, tail]),
      recognizer: recognizer,
      spans: [_spans.first, tail],
      preview: true,
    );
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_preview')));
    expect(_previews.single, (index: 1, start: _ms(19700), end: _ms(24300)));

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_next')));
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_preview')));
    // After the last row the preview borrows the last row's index.
    expect(_previews.last.index, 2);
    expect(_previews.last.start, _ms(55700));
  });

  testWidgets('no preview callback, no preview button', (tester) async {
    await _open(tester, document: _draft(), recognizer: _Recognizer());
    expect(find.byKey(const ValueKey('vocal_gap_preview')), findsNothing);
  });

  testWidgets('rows dropped at the edges are reported', (tester) async {
    final recognizer = _Recognizer()
      ..lines = [
        _line('kept', 20000, 22000),
        _line('edge', 24250, 25000),
      ];
    await _open(tester, document: _draft(), recognizer: recognizer);
    expect(find.textContaining('有 1 段识别结果落在范围边缘'), findsOneWidget);
    expect(find.text('插入 1 行'), findsOneWidget);
  });

  test('strings name the stretch and the counts', () {
    expect(LyricVocalCheckStrings.span(_span(20000, 24000)), '0:20.0–0:24.0');
    expect(
      LyricVocalCheckStrings.insertedMessage(2, _span(20000, 24000)),
      '已在 0:20.0–0:24.0 插入 2 行（未写入磁盘）',
    );
    expect(
      LyricVocalCheckStrings.dismissedMessage(_span(20000, 24000)),
      contains('不再提示'),
    );
    expect(LyricVocalCheckStrings.restoredMessage(3), '已恢复 3 行被人声检查删除的歌词（未写入磁盘）');
    expect(
      LyricVocalCheckStrings.restoredMessage(3, overlapping: 1),
      contains('其中 1 行和已有的行时间重叠'),
    );
    expect(
      LyricVocalCheckStrings.engineLabel(LyricSpanEngine.whisper),
      'Whisper',
    );
  });
}
