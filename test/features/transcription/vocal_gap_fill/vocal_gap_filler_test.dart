import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_gap_fill_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_gap_fill_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_gap_filler.dart';

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _row(String text, int start, int end, {String? id}) =>
    LyricLine(text: text, startTime: _ms(start), endTime: _ms(end), id: id);

/// A draft with rows at 0–4 s and 20–24 s and the given stretches of
/// singing without lyrics on its vocal check record.
LyricDocument _draft(
  List<LyricVocalCheckSpan> spans, {
  List<LyricLine>? lines,
  Duration? globalOffset,
}) => LyricDocument(
  language: 'zh',
  globalOffset: globalOffset,
  lines:
      lines ??
      [_row('第一句', 0, 4000, id: 'a'), _row('最后一句', 20000, 24000, id: 'b')],
  metadata: LyricVocalCheckRecord(uncoveredSpans: spans).writeTo(const {}),
);

class _Call {
  final Duration start;
  final Duration end;
  final LyricSpanEngine engine;

  const _Call(this.start, this.end, this.engine);
}

/// A scripted recogniser: [answers] maps an engine to what it returns (or
/// throws) for each call, in order.
class _Recognizer {
  _Recognizer(this.answers);

  final Map<LyricSpanEngine, List<Object>> answers;
  final calls = <_Call>[];

  Future<List<LyricLine>> call({
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
  }) async {
    calls.add(_Call(start, end, engine));
    final queue = answers[engine] ?? const [];
    final used = calls.where((call) => call.engine == engine).length - 1;
    final answer = used < queue.length ? queue[used] : const <LyricLine>[];
    if (answer is Exception) throw answer;
    if (answer is Error) throw answer;
    return answer as List<LyricLine>;
  }
}

void main() {
  const filler = VocalGapFiller();
  const gap = LyricVocalCheckSpan(Duration(seconds: 8), Duration(seconds: 11));

  group('skips', () {
    test('a draft without a vocal check record', () async {
      final recognizer = _Recognizer({});
      final draft = _draft(const []).copyWith(metadata: const {});
      final result = await filler.fill(
        draft,
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
      );
      expect(identical(result.document, draft), isTrue);
      expect(result.report.applied, isFalse);
      expect(result.report.skipReason, VocalGapFillSkipReason.noVocalCheck);
      expect(recognizer.calls, isEmpty);
    });

    test('a record whose stretches all have rows by now', () async {
      final recognizer = _Recognizer({});
      final draft = _draft(const [
        LyricVocalCheckSpan(Duration(seconds: 1), Duration(seconds: 3)),
      ]);
      final result = await filler.fill(
        draft,
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
      );
      expect(result.report.skipReason, VocalGapFillSkipReason.noGaps);
      expect(recognizer.calls, isEmpty);
    });

    test('no engine, listing every stretch as not tried', () async {
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [],
        recognize: _Recognizer({}).call,
      );
      expect(result.report.skipReason, VocalGapFillSkipReason.noEngine);
      expect(result.report.spans.single.outcome, VocalGapFillOutcome.notTried);
      expect(result.report.unattemptedSpans, 1);
    });

    test('a stretch cut short by the end of the song', () async {
      final draft = _draft(
        const [
          LyricVocalCheckSpan(
            Duration(seconds: 30),
            Duration(milliseconds: 30100),
          ),
        ],
        lines: [_row('前', 0, 4000)],
      );
      final recognizer = _Recognizer({});
      final result = await filler.fill(
        draft,
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
        audioDuration: _ms(30050),
      );
      // 29.7 s to the end of the song at 30.05 s is under half a second.
      expect(result.report.skipReason, VocalGapFillSkipReason.noWindows);
      expect(
        result.report.spans.single.outcome,
        VocalGapFillOutcome.unsendable,
      );
      expect(recognizer.calls, isEmpty);
    });

    test('a stretch longer than a window allows', () async {
      final draft = _draft(
        const [
          LyricVocalCheckSpan(Duration(seconds: 30), Duration(minutes: 3)),
        ],
        lines: [_row('前', 0, 4000)],
      );
      final recognizer = _Recognizer({});
      final result = await filler.fill(
        draft,
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
      );
      expect(result.report.skipReason, VocalGapFillSkipReason.noWindows);
      expect(
        result.report.spans.single.outcome,
        VocalGapFillOutcome.unsendable,
      );
      expect(recognizer.calls, isEmpty);
      expect(identical(result.document.lines, draft.lines), isTrue);
    });
  });

  group('fills', () {
    test('inserts the rows heard in a stretch, in place', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [
          [_row('漏掉的一句', 8100, 10800)],
        ],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );

      final lines = result.document.lines;
      expect(lines.map((line) => line.text), ['第一句', '漏掉的一句', '最后一句']);
      expect(lines[1].id, isNotNull);
      expect(lines[1].startTime, _ms(8100));
      // Window = stretch ± 300 ms.
      expect(recognizer.calls.single.start, _ms(7700));
      expect(recognizer.calls.single.end, _ms(11300));
      expect(recognizer.calls.single.engine, LyricSpanEngine.qwen);

      final report = result.report;
      expect(report.applied, isTrue);
      expect(report.filledSpans, 1);
      expect(report.insertedLines, 1);
      expect(report.fallbackSpans, 0);
      expect(report.spans.single.engine, LyricSpanEngine.qwen);
      expect(report.summary, '已自动补上 1 处漏句（1 行）');
    });

    test('records the inserted rows for the review queue', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [
          [_row('一', 8000, 9000), _row('二', 9000, 10900)],
        ],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
      );
      final record = LyricVocalGapFillRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(record.insertedLineIds, hasLength(2));
      expect(record.insertedIndices(result.document), [1, 2]);
      expect(record.filledSpans, [gap]);
      // The vocal check record is kept; its stretch is closed by the rows.
      final check = LyricVocalCheckRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(check.uncoveredSpans, [gap]);
      expect(check.openSpans(result.document), isEmpty);
    });

    test(
      'falls back to the other engine when the first hears nothing',
      () async {
        final recognizer = _Recognizer({
          LyricSpanEngine.qwen: [const <LyricLine>[]],
          LyricSpanEngine.whisper: [
            [_row('换引擎听到的', 8200, 10500)],
          ],
        });
        final result = await filler.fill(
          _draft(const [gap]),
          engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
          recognize: recognizer.call,
        );
        expect(recognizer.calls.map((call) => call.engine), [
          LyricSpanEngine.qwen,
          LyricSpanEngine.whisper,
        ]);
        expect(result.document.lines[1].text, '换引擎听到的');
        expect(result.report.fallbackSpans, 1);
        expect(result.report.spans.single.fellBack, isTrue);
        expect(result.report.spans.single.engine, LyricSpanEngine.whisper);
        expect(
          LyricVocalGapFillRecord.fromMetadata(
            result.document.metadata,
          )!.fallbackSpans,
          1,
        );
      },
    );

    test('falls back when the first engine fails', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [const LyricSpanRecognitionException('显存不足')],
        LyricSpanEngine.whisper: [
          [_row('备用', 8200, 10500)],
        ],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(result.report.filledSpans, 1);
      expect(result.report.spans.single.fellBack, isTrue);
    });

    test(
      'a result that only falls outside the window counts as empty',
      () async {
        final recognizer = _Recognizer({
          LyricSpanEngine.qwen: [
            [_row('窗外', 12000, 13000)],
          ],
          LyricSpanEngine.whisper: [const <LyricLine>[]],
        });
        final result = await filler.fill(
          _draft(const [gap]),
          engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
          recognize: recognizer.call,
        );
        expect(recognizer.calls, hasLength(2));
        expect(result.report.spans.single.outcome, VocalGapFillOutcome.empty);
        expect(result.document.lines, hasLength(2));
        expect(
          result.document.metadata.containsKey(
            LyricVocalGapFillRecord.metadataKey,
          ),
          isFalse,
        );
        expect(result.report.summary, '自动补全漏句没有识别出新歌词，1 处没有识别出文字');
      },
    );

    test('every engine failing reports the last error', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [const LyricSpanRecognitionException('一')],
        LyricSpanEngine.whisper: [const LyricSpanRecognitionException('二')],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(result.report.spans.single.outcome, VocalGapFillOutcome.failed);
      expect(result.report.spans.single.error, '二');
      expect(result.report.failedSpans, 1);
    });

    test('other exceptions fail the engine, not the step', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.whisper: [const FormatException('bad json')],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(result.report.applied, isTrue);
      expect(result.report.spans.single.error, contains('bad json'));
    });

    test('fills several stretches in one insertion', () async {
      const second = LyricVocalCheckSpan(
        Duration(seconds: 14),
        Duration(seconds: 17),
      );
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [
          [_row('甲', 8100, 10800)],
          [_row('乙', 14100, 16800)],
        ],
      });
      final result = await filler.fill(
        _draft(const [second, gap]),
        engines: const [LyricSpanEngine.qwen],
        recognize: recognizer.call,
      );
      expect(result.document.lines.map((line) => line.text), [
        '第一句',
        '甲',
        '乙',
        '最后一句',
      ]);
      // Timeline order, whatever order the record listed them in.
      expect(recognizer.calls.first.start, _ms(7700));
      expect(result.report.filledSpans, 2);
      expect(result.report.insertedLines, 2);
    });

    test(
      'moves rows onto the document timeline by the global offset',
      () async {
        final recognizer = _Recognizer({
          LyricSpanEngine.qwen: [
            [_row('偏移', 8600, 11000)],
          ],
        });
        final result = await filler.fill(
          _draft(const [gap], globalOffset: _ms(500)),
          engines: const [LyricSpanEngine.qwen],
          recognize: recognizer.call,
        );
        // The window is asked for on the audio's timeline...
        expect(recognizer.calls.single.start, _ms(8200));
        // ...and the row comes back on the document's.
        expect(result.document.lines[1].startTime, _ms(8100));
      },
    );

    test('the same engine is listed once', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.whisper: [const <LyricLine>[]],
      });
      final result = await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.whisper, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(recognizer.calls, hasLength(1));
      expect(result.report.engines, [LyricSpanEngine.whisper]);
    });

    test('reports which stretch is being recognised', () async {
      final progress = <VocalGapFillProgress>[];
      await filler.fill(
        _draft(const [gap]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: _Recognizer({}).call,
        onProgress: progress.add,
      );
      expect(progress.map((p) => (p.current, p.total, p.engine, p.fallback)), [
        (1, 1, LyricSpanEngine.qwen, false),
        (1, 1, LyricSpanEngine.whisper, true),
      ]);
      expect(progress.first.start, _ms(7700));
    });
  });

  group('stops', () {
    const later = LyricVocalCheckSpan(
      Duration(seconds: 14),
      Duration(seconds: 17),
    );

    test('on a busy runtime, keeping what was found', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [
          [_row('先找到的', 8100, 10800)],
          const LyricSpanRecognitionException('忙', busy: true),
        ],
      });
      final result = await filler.fill(
        _draft(const [gap, later]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      // No fallback after busy.
      expect(recognizer.calls, hasLength(2));
      expect(result.report.stopReason, VocalGapFillStopReason.busy);
      expect(result.report.filledSpans, 1);
      expect(result.report.spans.last.outcome, VocalGapFillOutcome.notTried);
      expect(result.document.lines[1].text, '先找到的');
      expect(result.report.summary, endsWith('（识别服务忙，提前结束）'));
    });

    test('on a cancel, without trying later stretches', () async {
      final recognizer = _Recognizer({
        LyricSpanEngine.qwen: [
          const LyricSpanRecognitionException('已取消', cancelled: true),
        ],
      });
      final result = await filler.fill(
        _draft(const [gap, later]),
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(recognizer.calls, hasLength(1));
      expect(result.report.stopReason, VocalGapFillStopReason.cancelled);
      expect(result.report.unattemptedSpans, 2);
      expect(result.document.lines, hasLength(2));
    });
  });

  group('budget', () {
    test('sends at most maxGaps stretches', () async {
      const policy = VocalGapFillPolicy(maxGaps: 1);
      const later = LyricVocalCheckSpan(
        Duration(seconds: 14),
        Duration(seconds: 17),
      );
      final recognizer = _Recognizer({});
      final result = await const VocalGapFiller(policy: policy).fill(
        _draft(const [gap, later]),
        engines: const [LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      expect(recognizer.calls, hasLength(1));
      expect(result.report.spans.map((span) => span.outcome), [
        VocalGapFillOutcome.empty,
        VocalGapFillOutcome.overBudget,
      ]);
    });

    test('sends at most maxAudio of windows', () async {
      const policy = VocalGapFillPolicy(maxAudio: Duration(seconds: 5));
      const later = LyricVocalCheckSpan(
        Duration(seconds: 14),
        Duration(seconds: 17),
      );
      final recognizer = _Recognizer({});
      final result = await const VocalGapFiller(policy: policy).fill(
        _draft(const [gap, later]),
        engines: const [LyricSpanEngine.whisper],
        recognize: recognizer.call,
      );
      // Each window is 3.6 s; the second would pass 5 s.
      expect(recognizer.calls, hasLength(1));
      expect(result.report.spans.last.outcome, VocalGapFillOutcome.overBudget);
      expect(result.report.summary, contains('1 处未识别'));
    });
  });
}
