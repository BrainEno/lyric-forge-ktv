import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_activity_lyric_gate.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(
  String text,
  int startMs,
  int endMs, {
  List<LyricWordTiming> words = const [],
}) => LyricLine(
  text: text,
  startTime: _ms(startMs),
  endTime: _ms(endMs),
  words: words,
);

VocalActivityProfile _profile(
  List<(int, int)> regions, {
  int durationMs = 120000,
  VocalActivityUnreliability? unreliability,
}) => VocalActivityProfile(
  duration: _ms(durationMs),
  referenceDb: -14,
  floorDb: -72,
  thresholdDb: -44,
  regions: [
    for (final (start, end) in regions)
      LyricVocalCheckSpan(_ms(start), _ms(end)),
  ],
  unreliability: unreliability,
);

LyricDocument _document(
  List<LyricLine> lines, {
  Map<String, dynamic> metadata = const {},
}) => LyricDocument(language: 'zh', lines: lines, metadata: metadata);

void main() {
  const gate = VocalActivityLyricGate();

  /// Singing 10–20 s, 25–35 s, 40–50 s; intro, interlude and outro silent.
  final song = _profile([(10000, 20000), (25000, 35000), (40000, 50000)]);

  test('deletes rows invented over the intro and outro', () {
    final draft = _document([
      _line('字幕由某某提供', 1000, 6000),
      _line('第一句歌词', 10000, 15000),
      _line('第二句歌词', 15000, 20000),
      _line('第三句歌词', 25000, 30000),
      _line('第四句歌词', 30000, 35000),
      _line('第五句歌词', 40000, 45000),
      _line('第六句歌词', 45000, 50000),
      _line('谢谢观看', 52000, 58000),
    ]);
    final result = gate.apply(draft, song, audioPath: 'v.wav');
    expect(result.document.lines.map((line) => line.text), [
      '第一句歌词',
      '第二句歌词',
      '第三句歌词',
      '第四句歌词',
      '第五句歌词',
      '第六句歌词',
    ]);
    expect(result.report.applied, isTrue);
    expect(result.report.audioPath, 'v.wav');
    final record = result.report.record;
    expect(record.removedLines.map((line) => line.text), [
      '字幕由某某提供',
      '谢谢观看',
    ]);
    expect(record.removedLines.first.start, _ms(1000));
    expect(record.removedLines.last.end, _ms(58000));
  });

  test('deletes a row invented over an interlude', () {
    final draft = _document([
      _line('第一句', 10000, 20000),
      _line('间奏里的假歌词', 21000, 24000),
      _line('第二句', 25000, 35000),
      _line('第三句', 40000, 50000),
    ]);
    final result = gate.apply(draft, song, audioPath: 'v.wav');
    expect(result.document.lines.map((line) => line.text), [
      '第一句',
      '第二句',
      '第三句',
    ]);
  });

  test('keeps a row whose singing is just outside its times', () {
    // The recogniser placed the row 150 ms after the phrase ended.
    final draft = _document([
      _line('第一句', 10000, 19800),
      _line('拖尾', 20150, 22000),
      _line('第二句', 25000, 35000),
    ]);
    final result = gate.apply(draft, song, audioPath: 'v.wav');
    // 20150 − 200 ms slack reaches back to 19950: 50 ms of singing, which
    // is under the minimum, so the row goes.
    expect(result.document.lines.map((line) => line.text), ['第一句', '第二句']);

    final loose = _document([
      _line('第一句', 10000, 19800),
      _line('拖尾', 20000, 22000),
      _line('第二句', 25000, 35000),
    ]);
    final kept = gate.apply(loose, song, audioPath: 'v.wav');
    // 200 ms of singing within the slack: kept.
    expect(kept.document.lines.map((line) => line.text), [
      '第一句',
      '拖尾',
      '第二句',
    ]);
  });

  test('keeps rows past the end of the analysed audio', () {
    final short = _profile([(10000, 20000)], durationMs: 30000);
    final draft = _document([
      _line('第一句', 10000, 20000),
      _line('超出分析范围', 29000, 33000),
    ]);
    final result = gate.apply(draft, short, audioPath: 'v.wav');
    expect(result.document.lines, hasLength(2));
  });

  test('empty and untimed rows are left alone', () {
    final draft = _document([
      _line('', 1000, 2000),
      _line('第一句', 10000, 20000),
      _line('没有时长', 5000, 5000),
    ]);
    final result = gate.apply(draft, song, audioPath: 'v.wav');
    expect(result.document.lines.map((line) => line.text), [
      '',
      '第一句',
      '没有时长',
    ]);
    expect(result.report.record.removedLines, isEmpty);
  });

  group('refuses to guess', () {
    test('an unreliable profile leaves the draft unchanged', () {
      final draft = _document([_line('第一句', 1000, 5000)]);
      final result = gate.apply(
        draft,
        _profile(
          const [],
          unreliability: VocalActivityUnreliability.lowContrast,
        ),
        audioPath: 'v.wav',
      );
      expect(identical(result.document, draft), isTrue);
      expect(result.report.applied, isFalse);
      expect(
        result.report.skipReason,
        VocalCheckSkipReason.unreliableProfile,
      );
      expect(result.report.toJson()['profile'], isNotNull);
    });

    test('a draft without timed rows is left unchanged', () {
      final draft = _document([_line('  ', 0, 1000)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(identical(result.document, draft), isTrue);
      expect(result.report.skipReason, VocalCheckSkipReason.noLines);
    });

    test('too many silent rows means the timeline is off', () {
      // Most rows sit 5 s off and land in silence.
      final draft = _document([
        _line('一', 5000, 9000),
        _line('二', 20500, 24500),
        _line('三', 35500, 39500),
        _line('四', 50500, 54500),
        _line('五', 12000, 16000),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(identical(result.document, draft), isTrue);
      expect(
        result.report.skipReason,
        VocalCheckSkipReason.tooManySilentLines,
      );
      expect(result.report.silentLines, 4);
      expect(result.report.toJson()['silentLines'], 4);
    });

    test('a short draft may still lose up to three invented rows', () {
      final draft = _document([
        _line('前奏假歌词', 1000, 5000),
        _line('第一句', 10000, 20000),
        _line('尾奏假歌词', 55000, 60000),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.document.lines.single.text, '第一句');
    });

    test('intro, interlude and outro rows go even from four rows', () {
      final draft = _document([
        _line('一', 1000, 5000),
        _line('二', 10000, 20000),
        _line('三', 21000, 24000),
        _line('四', 55000, 60000),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.document.lines.single.text, '二');
      expect(result.report.record.removedLines, hasLength(3));
    });

    test('a long draft may lose up to its silent share', () {
      // 20 rows: 7 silent is 35 %, 8 is more.
      List<LyricLine> rows(int silent) => [
        for (var index = 0; index < 20; index++)
          index < silent
              ? _line('假$index', 60000 + index * 2000, 61000 + index * 2000)
              : _line('真$index', 10000 + index * 400, 10300 + index * 400),
      ];
      VocalCheckReport check(int silent) =>
          gate.apply(_document(rows(silent)), song, audioPath: 'v.wav').report;
      expect(check(7).applied, isTrue);
      expect(check(7).record.removedLines, hasLength(7));
      expect(check(8).skipReason, VocalCheckSkipReason.tooManySilentLines);
    });
  });

  group('retiming', () {
    test('pulls a start that leads into silence onto the singing', () {
      final draft = _document([_line('起得太早', 7000, 15000)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final line = result.document.lines.single;
      expect(line.startTime, _ms(10000 - 120));
      expect(line.endTime, _ms(15000));
      expect(result.report.record.retimedLines, 1);
    });

    test('pulls an end that trails into silence back to the singing', () {
      final draft = _document([_line('收得太晚', 15000, 24000)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final line = result.document.lines.single;
      expect(line.startTime, _ms(15000));
      expect(line.endTime, _ms(20000 + 200));
    });

    test('tightens both ends of a row padded on both sides', () {
      final draft = _document([_line('两头都松', 22000, 38000)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final line = result.document.lines.single;
      expect(line.startTime, _ms(25000 - 120));
      expect(line.endTime, _ms(35000 + 200));
    });

    test('small gaps at the edges are not worth moving', () {
      final draft = _document([_line('差不多', 9700, 20400)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.document.lines.single.startTime, _ms(9700));
      expect(result.document.lines.single.endTime, _ms(20400));
      expect(result.report.record.retimedLines, 0);
    });

    test('never moves past the word timing', () {
      final draft = _document([
        _line(
          '有字级时间',
          6000,
          15000,
          words: [
            LyricWordTiming(text: '有', start: _ms(8000), end: _ms(9000)),
            LyricWordTiming(text: '字', start: _ms(10000), end: _ms(15000)),
          ],
        ),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final line = result.document.lines.single;
      expect(line.startTime, _ms(8000));
      expect(line.words, hasLength(2));
    });

    test('word timing that already covers the row keeps it', () {
      final draft = _document([
        _line(
          '字级覆盖',
          7000,
          15000,
          words: [
            LyricWordTiming(text: '字', start: _ms(7000), end: _ms(15000)),
          ],
        ),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(
        identical(result.document.lines.single, draft.lines.single),
        isTrue,
      );
      expect(result.report.record.retimedLines, 0);
    });

    test('never stretches a row beyond its own times', () {
      final draft = _document([_line('在里面', 11000, 19000)]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.document.lines.single.startTime, _ms(11000));
      expect(result.document.lines.single.endTime, _ms(19000));
    });

    test('a row that would become too short keeps its times', () {
      const strict = VocalActivityLyricGate(
        minimumRetimedLength: Duration(seconds: 1),
      );
      // Only 200 ms of singing inside a long row.
      final blip = _profile([(10000, 10200), (30000, 40000)]);
      final draft = _document([
        _line('很短的声音', 8000, 14000),
        _line('正常', 30000, 40000),
      ]);
      final result = strict.apply(draft, blip, audioPath: 'v.wav');
      expect(result.document.lines.first.startTime, _ms(8000));
      expect(result.document.lines.first.endTime, _ms(14000));
    });

    test('rows past the analysed audio are not retimed', () {
      final short = _profile([(10000, 20000)], durationMs: 22000);
      final draft = _document([_line('跨过结尾', 7000, 25000)]);
      final result = gate.apply(draft, short, audioPath: 'v.wav');
      expect(result.document.lines.single.startTime, _ms(7000));
    });

    test('rows only the second engine heard keep their times', () {
      const padded = LyricLine(
        text: '只有备用引擎听到',
        startTime: Duration(seconds: 7),
        endTime: Duration(seconds: 15),
      );
      final draft = _document(
        [padded, _line('第二句', 22000, 35000)],
        metadata: {
          SecondaryOnlySuggestion.metadataKey: SecondaryOnlySuggestion.wrap(
            const [
              SecondaryOnlySuggestion(
                text: '只有备用引擎听到',
                startMs: 7000,
                endMs: 15000,
                engine: 'whisper',
              ),
            ],
          ),
        },
      );
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(identical(result.document.lines.first, padded), isTrue);
      expect(result.document.lines.last.startTime, _ms(25000 - 120));
      expect(result.report.record.retimedLines, 1);
      final resolved = SecondaryOnlySuggestion.resolve(result.document);
      expect(resolved.keys.toList(), [0]);
    });

    test('keeps the row identity and flags while retiming', () {
      final draft = _document([
        const LyricLine(
          text: '副歌',
          startTime: Duration(seconds: 7),
          endTime: Duration(seconds: 15),
          isChorus: true,
          confidence: 80,
          id: 'row-1',
        ),
      ]);
      final line = gate
          .apply(draft, song, audioPath: 'v.wav')
          .document
          .lines
          .single;
      expect(line.id, 'row-1');
      expect(line.isChorus, isTrue);
      expect(line.confidence, 80);
      expect(line.startTime, isNot(const Duration(seconds: 7)));
    });
  });

  group('uncovered singing', () {
    test('records singing no row covers', () {
      final draft = _document([
        _line('第一句', 10000, 20000),
        _line('第三句', 40000, 50000),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.report.record.uncoveredSpans, [
        LyricVocalCheckSpan(_ms(25000), _ms(35000)),
      ]);
    });

    test('a partly covered phrase leaves the rest uncovered', () {
      final draft = _document([
        _line('第一句', 10000, 14000),
        _line('第二句', 25000, 35000),
        _line('第三句', 40000, 50000),
      ]);
      final spans = gate
          .apply(draft, song, audioPath: 'v.wav')
          .report
          .record
          .uncoveredSpans;
      expect(spans, [LyricVocalCheckSpan(_ms(14300), _ms(20000))]);
    });

    test('short uncovered singing is not reported', () {
      final draft = _document([
        _line('第一句', 10000, 19500),
        _line('第二句', 25000, 35000),
        _line('第三句', 40000, 50000),
      ]);
      expect(
        gate
            .apply(draft, song, audioPath: 'v.wav')
            .report
            .record
            .uncoveredSpans,
        isEmpty,
      );
    });

    test('nearby pieces join into one stretch', () {
      final choppy = _profile([
        (10000, 10800),
        (11300, 12100),
        (12600, 13400),
        (30000, 40000),
      ]);
      final draft = _document([_line('后面', 30000, 40000)]);
      final spans = gate
          .apply(draft, choppy, audioPath: 'v.wav')
          .report
          .record
          .uncoveredSpans;
      expect(spans, [LyricVocalCheckSpan(_ms(10000), _ms(13400))]);
    });

    test('a row between two pieces keeps them apart', () {
      const tight = VocalActivityLyricGate(
        coverTolerance: Duration(milliseconds: 100),
      );
      final profile = _profile([
        (10000, 11000),
        (11250, 11450),
        (11700, 12700),
      ]);
      final draft = _document([_line('中间短句', 11200, 11500)]);
      final record = tight
          .apply(draft, profile, audioPath: 'v.wav')
          .report
          .record;
      expect(record.removedLines, isEmpty);
      // 700 ms apart, but each side alone is under 1.2 s of singing.
      expect(record.uncoveredSpans, isEmpty);

      // Without the row the two sides are one missed stretch.
      final bare = tight.apply(
        _document([_line('别处', 30000, 31000)]),
        _profile([(10000, 11000), (11700, 12700), (30000, 31000)]),
        audioPath: 'v.wav',
      );
      expect(bare.report.record.uncoveredSpans, [
        LyricVocalCheckSpan(_ms(10000), _ms(12700)),
      ]);
    });

    test('records the missed tail after deleting an interlude row', () {
      // A long silent row over an interlude followed by a missed phrase.
      final profile = _profile([(10000, 20000), (40000, 50000)]);
      final draft = _document([
        _line('第一句', 10000, 20000),
        _line('间奏假歌词', 22000, 30000),
        _line('第三句', 40000, 46000),
      ]);
      final result = gate.apply(draft, profile, audioPath: 'v.wav');
      expect(result.report.record.removedLines.single.text, '间奏假歌词');
      expect(result.report.record.uncoveredSpans, [
        LyricVocalCheckSpan(_ms(46300), _ms(50000)),
      ]);
    });
  });

  group('document metadata', () {
    test('stores the record in the document', () {
      final draft = _document(
        [_line('假歌词', 1000, 5000), _line('第一句', 10000, 20000)],
        metadata: const {'primaryEngine': 'qwen3-asr-1.7b'},
      );
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final metadata = result.document.metadata;
      expect(metadata['primaryEngine'], 'qwen3-asr-1.7b');
      final record = LyricVocalCheckRecord.fromMetadata(metadata)!;
      expect(record.removedLines.single.text, '假歌词');
      expect(record.uncoveredSpans, hasLength(2));
    });

    test('a clean draft still records that the check ran', () {
      final draft = _document([
        _line('第一句', 10000, 20000),
        _line('第二句', 25000, 35000),
        _line('第三句', 40000, 50000),
      ]);
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final record = LyricVocalCheckRecord.fromMetadata(
        result.document.metadata,
      )!;
      expect(record.isEmpty, isTrue);
      expect(result.report.applied, isTrue);
    });

    test('row-indexed review evidence follows the remaining rows', () {
      final draft = _document(
        [
          _line('前奏假歌词', 1000, 5000),
          _line('第一句', 10000, 20000),
          _line('第二句', 25000, 35000),
        ],
        metadata: {
          'fallbackCandidates': [
            {'lineIndex': 0, 'text': '假的备选'},
            {'lineIndex': 2, 'text': '第二句备选'},
          ],
          'fallbackCandidateCount': 2,
          LyricIndexedReviewMetadata.secondaryOnlyIndicesKey: [0, 2],
          LyricIndexedReviewMetadata.secondaryOnlyCountKey: 2,
        },
      );
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      final metadata = result.document.metadata;
      final candidates = metadata['fallbackCandidates'] as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['lineIndex'], 1);
      expect((candidates.single as Map)['text'], '第二句备选');
      expect(metadata[LyricIndexedReviewMetadata.candidateCountKey], 1);
      expect(metadata[LyricIndexedReviewMetadata.secondaryOnlyIndicesKey], [
        1,
      ]);
      expect(metadata[LyricIndexedReviewMetadata.secondaryOnlyCountKey], 1);
    });

    test('nothing removed leaves the review evidence untouched', () {
      final evidence = [
        {'lineIndex': 0, 'text': '备选'},
      ];
      final draft = _document(
        [_line('第一句', 7000, 20000)],
        metadata: {'fallbackCandidates': evidence},
      );
      final result = gate.apply(draft, song, audioPath: 'v.wav');
      expect(result.document.metadata['fallbackCandidates'], evidence);
      expect(result.report.record.retimedLines, 1);
    });
  });

  test('the report serialises what happened', () {
    final draft = _document([
      _line('假歌词', 1000, 5000),
      _line('第一句', 7000, 20000),
    ]);
    final json = gate.apply(draft, song, audioPath: 'v.wav').report.toJson();
    expect(json['applied'], isTrue);
    expect(json['skipReason'], isNull);
    expect(json['audioPath'], 'v.wav');
    expect(json['removedLines'], 1);
    expect(json['retimedLines'], 1);
    expect(json['uncoveredSpans'], 2);
    expect(json.containsKey('silentLines'), isFalse);
    expect(json.containsKey('error'), isFalse);
    expect((json['profile'] as Map)['regions'], 3);
  });

  test('a skipped report without a profile serialises its reason', () {
    const report = VocalCheckReport.skipped(
      VocalCheckSkipReason.unreadableAudio,
      error: 'missing',
    );
    final json = report.toJson();
    expect(json['applied'], isFalse);
    expect(json['skipReason'], 'unreadableAudio');
    expect(json['profile'], isNull);
    expect(json['error'], 'missing');
    expect(json['removedLines'], 0);
  });
}
