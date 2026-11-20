import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _s(double value) => Duration(milliseconds: (value * 1000).round());

LyricLine _line(String text, double start, double end) =>
    LyricLine(text: text, startTime: _s(start), endTime: _s(end));

LyricVocalCheckSpan _span(double start, double end) =>
    LyricVocalCheckSpan(_s(start), _s(end));

LyricDocument _document(
  List<LyricLine> lines, {
  LyricVocalCheckRecord? record,
}) => LyricDocument(
  language: 'zh',
  lines: lines,
  metadata: {
    'primaryEngine': 'qwen3-asr-1.7b',
    if (record != null) LyricVocalCheckRecord.metadataKey: record.toJson(),
  },
);

RecognitionReviewSummary _summary(LyricDocument document) =>
    RecognitionReviewSummary.fromDocument(
      document,
      LyricReviewQueue.build(document),
    );

const _record = LyricVocalCheckRecord(
  removedLines: [
    LyricVocalCheckRemovedLine(
      text: '字幕由某某提供',
      start: Duration(seconds: 1),
      end: Duration(seconds: 5),
    ),
    LyricVocalCheckRemovedLine(
      text: ' 间奏里编出来的 ',
      start: Duration(seconds: 60),
      end: Duration(seconds: 64),
    ),
    LyricVocalCheckRemovedLine(
      text: '谢谢观看',
      start: Duration(seconds: 200),
      end: Duration(seconds: 204),
    ),
  ],
  retimedLines: 5,
  uncoveredSpans: [
    LyricVocalCheckSpan(Duration(seconds: 75), Duration(seconds: 79)),
  ],
);

void main() {
  group('summary', () {
    test('reads the record and its open stretches', () {
      final summary = _summary(
        _document([_line('第一句', 10, 15)], record: _record),
      );
      expect(summary.vocalCheck?.removedLines, hasLength(3));
      expect(summary.openVocalSpans, [_span(75, 79)]);
    });

    test('a row typed into a stretch closes it', () {
      final summary = _summary(
        _document([
          _line('第一句', 10, 15),
          _line('补写的歌词', 75.5, 78.5),
        ], record: _record),
      );
      expect(summary.vocalCheck, isNotNull);
      expect(summary.openVocalSpans, isEmpty);
    });

    test('documents without a record have no vocal check', () {
      final summary = _summary(_document([_line('第一句', 10, 15)]));
      expect(summary.vocalCheck, isNull);
      expect(summary.openVocalSpans, isEmpty);
    });
  });

  group('wording', () {
    test('clock writes minutes and tenths', () {
      expect(LyricRecognitionSummaryCard.clock(Duration.zero), '0:00.0');
      expect(LyricRecognitionSummaryCard.clock(_s(5.26)), '0:05.3');
      expect(LyricRecognitionSummaryCard.clock(_s(59.96)), '1:00.0');
      expect(LyricRecognitionSummaryCard.clock(_s(75)), '1:15.0');
      expect(LyricRecognitionSummaryCard.clock(_s(612.4)), '10:12.4');
    });

    test('names the first stretches and counts the rest', () {
      final one = _summary(_document([_line('第一句', 10, 15)], record: _record));
      expect(
        LyricRecognitionSummaryCard.vocalSpansLine(one),
        '有人声但没有歌词：1:15.0–1:19.0。试听后可补写，或选中相邻的行用“重新识别这一段”',
      );

      final many = _summary(
        _document(
          [_line('第一句', 10, 15)],
          record: LyricVocalCheckRecord(
            uncoveredSpans: [
              _span(20, 22),
              _span(30, 32),
              _span(40, 42),
              _span(50, 52),
              _span(60, 62),
            ],
          ),
        ),
      );
      final line = LyricRecognitionSummaryCard.vocalSpansLine(many)!;
      expect(line, contains('0:20.0–0:22.0、0:30.0–0:32.0、0:40.0–0:42.0 等 5 处'));
      expect(line, isNot(contains('0:50.0')));
    });

    test('no open stretch means no line', () {
      final summary = _summary(
        _document([
          _line('第一句', 10, 15),
        ], record: const LyricVocalCheckRecord()),
      );
      expect(LyricRecognitionSummaryCard.vocalSpansLine(summary), isNull);
    });

    test('describes what the check changed', () {
      final lines = LyricRecognitionSummaryCard.vocalCheckLines(_record);
      expect(lines, hasLength(2));
      expect(lines.first, contains('删除了 3 行没人唱的歌词'));
      expect(lines.first, contains('“字幕由某某提供”、“间奏里编出来的”等'));
      expect(lines.first, contains('前奏、间奏或尾奏'));
      expect(lines.last, '按人声收紧了 5 行的起止时间');
    });

    test('two removed rows are listed without 等', () {
      final lines = LyricRecognitionSummaryCard.vocalCheckLines(
        const LyricVocalCheckRecord(
          removedLines: [
            LyricVocalCheckRemovedLine(
              text: '一',
              start: Duration.zero,
              end: Duration(seconds: 1),
            ),
            LyricVocalCheckRemovedLine(
              text: '二',
              start: Duration(seconds: 2),
              end: Duration(seconds: 3),
            ),
          ],
        ),
      );
      expect(lines.single, contains('（“一”、“二”）'));
    });

    test('a check that changed nothing says so', () {
      expect(
        LyricRecognitionSummaryCard.vocalCheckLines(
          const LyricVocalCheckRecord(),
        ),
        ['人声检查没有发现需要删除或收紧的行'],
      );
      expect(LyricRecognitionSummaryCard.vocalCheckLines(null), isEmpty);
    });
  });

  group('card', () {
    Future<void> pump(WidgetTester tester, LyricDocument document) async {
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
                  summary: _summary(document),
                  onStartReview: null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows open stretches without expanding', (tester) async {
      await pump(tester, _document([_line('第一句', 10, 15)], record: _record));
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_spans')),
        findsOneWidget,
      );
      expect(find.textContaining('1:15.0–1:19.0'), findsOneWidget);
      expect(find.textContaining('有人声没歌词', findRichText: true), findsOneWidget);
      expect(find.textContaining('1 处', findRichText: true), findsOneWidget);
      // The change log waits for the expanded card.
      expect(find.textContaining('删除了 3 行'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('删除了 3 行'), findsOneWidget);
      expect(find.textContaining('收紧了 5 行'), findsOneWidget);
    });

    testWidgets('closed stretches leave only the zero count', (tester) async {
      await pump(
        tester,
        _document([_line('第一句', 10, 15), _line('补写', 75, 79)], record: _record),
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_spans')),
        findsNothing,
      );
      expect(find.textContaining('0 处', findRichText: true), findsOneWidget);
    });

    testWidgets('no record, no vocal metric', (tester) async {
      await pump(tester, _document([_line('第一句', 10, 15)]));
      expect(find.textContaining('有人声没歌词', findRichText: true), findsNothing);
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_vocal_spans')),
        findsNothing,
      );
    });
  });
}
