import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_vocal_gap_batch_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricVocalCheckSpan _span(int startMs, int endMs) =>
    LyricVocalCheckSpan(_ms(startMs), _ms(endMs));

/// Three stretches: windows start at 19.7 s, 39.7 s and 59.7 s.
final _spans = [
  _span(20000, 24000),
  _span(40000, 43000),
  _span(60000, 63000),
];

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
        _line('verse one', 10000, 14000, id: 'a'),
        _line('verse two', 30000, 34000, id: 'b'),
        _line('verse three', 50000, 54000, id: 'c'),
      ],
  metadata: {
    LyricVocalCheckRecord.metadataKey: LyricVocalCheckRecord(
      uncoveredSpans: spans ?? _spans,
    ).toJson(),
  },
);

typedef _Call = ({Duration start, Duration end, LyricSpanEngine engine});

/// Answers by the window's start (whole seconds on the audio's timeline)
/// and engine; anything not listed recognises nothing.
class _Recognizer implements LyricSpanRecognizer {
  final calls = <_Call>[];
  final answers = <(int, LyricSpanEngine), List<LyricLine>>{};
  final failures = <(int, LyricSpanEngine), LyricSpanRecognitionException>{};

  /// Holds every request until completed.
  Completer<void>? gate;
  int cancels = 0;

  void answer(int second, LyricSpanEngine engine, List<LyricLine> lines) =>
      answers[(second, engine)] = lines;

  @override
  Future<LyricRecognizedSpan> recognize({
    required String projectId,
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
  }) async {
    calls.add((start: start, end: end, engine: engine));
    final pending = gate;
    if (pending != null) await pending.future;
    final key = (start.inSeconds, engine);
    final failure = failures[key];
    if (failure != null) throw failure;
    return LyricRecognizedSpan(
      lines: answers[key] ?? const [],
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
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const LyricSpanRecognitionException('cancelled', cancelled: true),
      );
    }
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
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
  Duration? audioDuration,
  bool preview = false,
}) async {
  LyricBatchTextEdit? result;
  _previews.clear();
  tester.view.physicalSize = const Size(1200, 2400);
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
                  result = await showLyricVocalGapBatchDialog(
                    context,
                    document: document,
                    spans: spans ?? _spans,
                    projectId: 'project',
                    recognizer: recognizer,
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

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

FilledButton _confirm(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('vocal_gap_batch_confirm')),
);

bool? _checked(WidgetTester tester, int index) => tester
    .widget<Checkbox>(find.byKey(ValueKey('vocal_gap_batch_check_$index')))
    .value;

List<String> _texts(LyricDocument document) => [
  for (final line in document.lines) line.text,
];

void main() {
  testWidgets('recognises every stretch and inserts them in one edit', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('found at twenty', 20000, 23000)])
      ..answer(39, LyricSpanEngine.qwen, [
        _line('found at forty', 40000, 41500),
        _line('and more', 41500, 43000),
      ])
      ..answer(59, LyricSpanEngine.qwen, [_line('found at sixty', 60000, 62000)]);
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );

    expect(find.text(LyricVocalGapBatchStrings.title), findsOneWidget);
    expect([for (final call in recognizer.calls) call.start], [
      _ms(19700),
      _ms(39700),
      _ms(59700),
    ]);
    expect(
      recognizer.calls.every((call) => call.engine == LyricSpanEngine.qwen),
      isTrue,
    );
    expect(_text(tester, 'vocal_gap_batch_summary'), '3 处识别出歌词');
    expect(_text(tester, 'vocal_gap_batch_status_1'), 'Qwen3-ASR 1.7B 识别出 2 行');
    for (var index = 0; index < 3; index++) {
      expect(_checked(tester, index), isTrue);
    }
    expect(find.text('插入 4 行（3 处）'), findsOneWidget);
    expect(find.textContaining('found at forty'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_confirm')));
    final edit = result()!;
    expect(_texts(edit.document), [
      'verse one',
      'found at twenty',
      'verse two',
      'found at forty',
      'and more',
      'verse three',
      'found at sixty',
    ]);
    expect(edit.selectedLineIndex, 1);
    expect(edit.label, LyricVocalGapBatchStrings.title);
    expect(edit.message, '已在 3 处插入 4 行（未写入磁盘）');
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(record.openSpans(edit.document), isEmpty);
  });

  testWidgets('unchecked stretches are left out', (tester) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('keep', 20000, 23000)])
      ..answer(39, LyricSpanEngine.qwen, [_line('drop', 40000, 42000)]);
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      spans: _spans.sublist(0, 2),
    );
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_check_1')));
    expect(_checked(tester, 1), isFalse);
    expect(find.text('插入 1 行（1 处）'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_confirm')));
    expect(_texts(result()!.document), [
      'verse one',
      'keep',
      'verse two',
      'verse three',
    ]);
  });

  testWidgets('a stretch the first engine misses is tried with the other', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.whisper, [_line('whisper heard', 20000, 23000)]);
    await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      spans: _spans.sublist(0, 1),
    );
    expect(recognizer.calls.map((call) => call.engine), [
      LyricSpanEngine.qwen,
      LyricSpanEngine.whisper,
    ]);
    expect(
      _text(tester, 'vocal_gap_batch_status_0'),
      'Whisper large-v3 识别出 1 行',
    );
    expect(find.textContaining('第一个引擎没有识别出'), findsOneWidget);
    expect(_checked(tester, 0), isTrue);
  });

  testWidgets('a failure also falls back to the other engine', (tester) async {
    final recognizer = _Recognizer()
      ..failures[(19, LyricSpanEngine.qwen)] =
          const LyricSpanRecognitionException('Qwen 出错了')
      ..answer(19, LyricSpanEngine.whisper, [_line('rescued', 20000, 23000)]);
    await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      spans: _spans.sublist(0, 1),
    );
    expect(recognizer.calls, hasLength(2));
    expect(_checked(tester, 0), isTrue);
  });

  testWidgets('without the fallback only the chosen engine runs', (
    tester,
  ) async {
    final recognizer = _Recognizer()..gate = Completer<void>();
    await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      spans: _spans.sublist(0, 1),
    );
    // Stop the automatic run, switch the fallback off and pick Whisper.
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_stop')));
    recognizer
      ..gate = null
      ..calls.clear();
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_fallback')));
    await _tap(
      tester,
      find.byKey(const ValueKey('vocal_gap_batch_engine_whisper')),
    );
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_rerun')));
    expect(recognizer.calls.map((call) => call.engine), [
      LyricSpanEngine.whisper,
    ]);
    expect(
      _text(tester, 'vocal_gap_batch_status_0'),
      LyricVocalGapBatchStrings.nothingFound,
    );
  });

  testWidgets('nothing found can be marked as having no lyrics', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('found', 20000, 23000)]);
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
    );
    expect(
      _text(tester, 'vocal_gap_batch_summary'),
      '1 处识别出歌词，2 处没有识别出',
    );
    expect(_checked(tester, 1), isFalse);
    final check = tester.widget<Checkbox>(
      find.byKey(const ValueKey('vocal_gap_batch_check_1')),
    );
    expect(check.onChanged, isNull);
    expect(find.text(LyricVocalGapBatchStrings.dismissEmptyLabel(2)), findsOneWidget);

    await _tap(
      tester,
      find.byKey(const ValueKey('vocal_gap_batch_dismiss_empty')),
    );
    expect(find.text('插入 1 行（1 处），标记 2 处没有歌词'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_confirm')));
    final edit = result()!;
    expect(edit.message, '已在 1 处插入 1 行，已标记 2 处没有歌词（未写入磁盘）');
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(record.uncoveredSpans, [_spans.first]);
    expect(record.dismissedSpans, 2);
    expect(record.openSpans(edit.document), isEmpty);
  });

  testWidgets('only marking stretches is a valid edit', (tester) async {
    final recognizer = _Recognizer();
    final result = await _open(
      tester,
      document: _draft(),
      recognizer: recognizer,
      spans: _spans.sublist(0, 1),
    );
    expect(_confirm(tester).onPressed, isNull);
    expect(find.text('没有可插入的歌词'), findsOneWidget);

    await _tap(
      tester,
      find.byKey(const ValueKey('vocal_gap_batch_dismiss_empty')),
    );
    expect(_confirm(tester).onPressed, isNotNull);
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_confirm')));
    final edit = result()!;
    expect(edit.selectedLineIndex, isNull);
    expect(edit.document.lines, hasLength(3));
    expect(edit.message, '已标记 1 处没有歌词（未写入磁盘）');
  });

  testWidgets('a busy runtime ends the run and the rest can run again', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('found', 20000, 23000)])
      ..failures[(39, LyricSpanEngine.qwen)] =
          const LyricSpanRecognitionException('运行时正忙', busy: true);
    await _open(tester, document: _draft(), recognizer: recognizer);
    // No fallback for a busy runtime and no third request.
    expect(recognizer.calls, hasLength(2));
    expect(find.byKey(const ValueKey('vocal_gap_batch_notice')), findsOneWidget);
    expect(_text(tester, 'vocal_gap_batch_status_1'), '运行时正忙');
    expect(_text(tester, 'vocal_gap_batch_status_2'), '等待识别');
    expect(
      _text(tester, 'vocal_gap_batch_summary'),
      '1 处识别出歌词，1 处识别失败，1 处还没有识别',
    );
    // What was found can already be inserted.
    expect(_confirm(tester).onPressed, isNotNull);
    expect(find.text(LyricVocalGapBatchStrings.rerunLabel(2)), findsOneWidget);

    recognizer.failures.clear();
    recognizer.answer(39, LyricSpanEngine.qwen, [_line('later', 40000, 42000)]);
    recognizer.calls.clear();
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_rerun')));
    expect([for (final call in recognizer.calls) call.start.inSeconds], [
      39,
      59,
      59,
    ]);
    expect(_checked(tester, 0), isTrue, reason: 'found results are kept');
    expect(_checked(tester, 1), isTrue);
    expect(find.byKey(const ValueKey('vocal_gap_batch_notice')), findsNothing);
  });

  testWidgets('stopping cancels the request and keeps what was found', (
    tester,
  ) async {
    final recognizer = _Recognizer()..gate = Completer<void>();
    await _open(tester, document: _draft(), recognizer: recognizer);
    expect(find.byKey(const ValueKey('vocal_gap_batch_progress')), findsOneWidget);
    expect(find.text(LyricVocalGapBatchStrings.progress(1, 3)), findsOneWidget);
    expect(_text(tester, 'vocal_gap_batch_status_0'), '正在识别…');
    expect(_confirm(tester).onPressed, isNull);
    final whisper = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('vocal_gap_batch_engine_whisper')),
    );
    expect(whisper.onSelected, isNull);

    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_stop')));
    expect(recognizer.cancels, 1);
    expect(recognizer.calls, hasLength(1));
    expect(_text(tester, 'vocal_gap_batch_status_0'), '已停止');
    expect(_text(tester, 'vocal_gap_batch_status_1'), '等待识别');
    expect(find.text(LyricVocalGapBatchStrings.stopped), findsOneWidget);
    expect(find.text(LyricVocalGapBatchStrings.rerunLabel(3)), findsOneWidget);
  });

  testWidgets('the progress counts the stretches of the current run', (
    tester,
  ) async {
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('found', 20000, 23000)]);
    await _open(tester, document: _draft(), recognizer: recognizer);
    recognizer.gate = Completer<void>();
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_rerun')));
    // Two stretches had nothing; the found one is not run again.
    expect(find.text(LyricVocalGapBatchStrings.progress(1, 2)), findsOneWidget);
    expect(_checked(tester, 0), isTrue);
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

  testWidgets('stretches that cannot be sent are listed, not sent', (
    tester,
  ) async {
    final squeezed = _span(14050, 14250);
    final document = _draft(
      spans: [squeezed, _span(20000, 24000)],
      lines: [
        _line('one', 10000, 14000),
        _line('two', 14300, 18000),
        _line('three', 30000, 34000),
      ],
    );
    final recognizer = _Recognizer()
      ..answer(19, LyricSpanEngine.qwen, [_line('found', 20000, 23000)]);
    await _open(
      tester,
      document: document,
      recognizer: recognizer,
      spans: [squeezed, _span(20000, 24000)],
    );
    expect(recognizer.calls, hasLength(1));
    expect(_text(tester, 'vocal_gap_batch_status_0'), contains('不到 0.5 秒'));
    expect(
      _text(tester, 'vocal_gap_batch_summary'),
      '1 处识别出歌词，1 处无法单独识别',
    );
    expect(find.byKey(const ValueKey('vocal_gap_batch_rerun')), findsNothing);
  });

  testWidgets('works on the audio timeline with a global offset', (
    tester,
  ) async {
    // The audio is 1 s behind the document; windows are asked for at
    // 20.7 s, recognised rows come back on the audio's timeline.
    final recognizer = _Recognizer()
      ..answer(20, LyricSpanEngine.qwen, [_line('shifted', 21000, 24000)]);
    final result = await _open(
      tester,
      document: _draft(offset: _ms(1000)),
      recognizer: recognizer,
      spans: _spans.sublist(0, 1),
    );
    expect(recognizer.calls.single.start, _ms(20700));
    expect(recognizer.calls.single.end, _ms(25300));
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_confirm')));
    final inserted = result()!.document.lines[1];
    expect(inserted.startTime, _ms(20000));
    expect(inserted.endTime, _ms(23000));
  });

  testWidgets('previews each window anchored on a neighbouring row', (
    tester,
  ) async {
    final tail = _span(60000, 63000);
    await _open(
      tester,
      document: _draft(spans: [_spans.first, tail]),
      recognizer: _Recognizer(),
      spans: [_spans.first, tail],
      preview: true,
    );
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_preview_0')));
    expect(_previews.single, (index: 1, start: _ms(19700), end: _ms(24300)));
    await _tap(tester, find.byKey(const ValueKey('vocal_gap_batch_preview_1')));
    expect(_previews.last.index, 2);
  });

  test('strings', () {
    expect(
      LyricVocalGapBatchStrings.summary(
        found: 0,
        empty: 0,
        failed: 0,
        skipped: 0,
        waiting: 0,
      ),
      '0 处识别出歌词',
    );
    expect(
      LyricVocalGapBatchStrings.confirmLabel(rows: 0, gaps: 0, dismissed: 2),
      '标记 2 处没有歌词',
    );
    expect(LyricVocalGapBatchStrings.progress(2, 5), '正在识别第 2 / 5 处…');
    expect(
      LyricVocalGapBatchStrings.fallbackNote('Whisper large-v3'),
      contains('Whisper large-v3'),
    );
  });
}
