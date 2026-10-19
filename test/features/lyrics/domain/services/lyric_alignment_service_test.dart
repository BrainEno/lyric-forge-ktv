import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricAlignmentService();

  LyricDocument document(List<LyricLine> lines) {
    return LyricDocument(language: 'zh', lines: lines);
  }

  LyricLine asr(
    String text, {
    int startMs = 0,
    int endMs = 4000,
    int confidence = 90,
  }) {
    return LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      confidence: confidence,
    );
  }

  ReferenceLyricLine reference(String text, {int? startMs, int? endMs}) {
    return ReferenceLyricLine(
      text: text,
      startTime: startMs == null ? null : Duration(milliseconds: startMs),
      endTime: endMs == null ? null : Duration(milliseconds: endMs),
    );
  }

  test('maps identical lines and keeps ASR timestamps', () {
    final result = service.align(
      document: document([
        asr('月亮代表我的心', startMs: 0, endMs: 4000),
        asr('轻轻的一个吻', startMs: 4000, endMs: 8000),
      ]),
      referenceLines: [reference('月亮代表我的心'), reference('轻轻的一个吻')],
    );

    expect(result.entries, hasLength(2));
    expect(result.entries.map((entry) => entry.status), [
      ReferenceLineAlignmentStatus.identical,
      ReferenceLineAlignmentStatus.identical,
    ]);
    expect(result.entries[0].asrLineIndex, 0);
    expect(result.entries[0].startTime, Duration.zero);
    expect(result.entries[0].endTime, const Duration(seconds: 4));
    expect(result.entries[1].asrLineIndex, 1);
    expect(result.entries[1].startTime, const Duration(seconds: 4));
    expect(result.missingReferenceIndices, isEmpty);
    expect(result.unmatchedAsrIndices, isEmpty);
    expect(result.asrLines.map((line) => line.status), [
      AsrLineAlignmentStatus.matched,
      AsrLineAlignmentStatus.matched,
    ]);
  });

  test('marks ASR typos as replace while preserving timing', () {
    final result = service.align(
      document: document([asr('月亮代表我的星', startMs: 2000, endMs: 6000)]),
      referenceLines: [reference('月亮代表我的心')],
    );

    final entry = result.entries.single;
    expect(entry.status, ReferenceLineAlignmentStatus.replace);
    expect(entry.asrLineIndex, 0);
    expect(entry.similarity, greaterThanOrEqualTo(0.5));
    expect(entry.similarity, lessThan(1));
    expect(entry.startTime, const Duration(seconds: 2));
    expect(entry.endTime, const Duration(seconds: 6));
    expect(result.asrLines.single.status, AsrLineAlignmentStatus.toBeCorrected);
  });

  test('marks reference lines missed by ASR as missing without times', () {
    final result = service.align(
      document: document([
        asr('第一句', startMs: 0, endMs: 2000),
        asr('第三句', startMs: 4000, endMs: 6000),
      ]),
      referenceLines: [reference('第一句'), reference('漏掉的第二句'), reference('第三句')],
    );

    final missing = result.entries[1];
    expect(missing.status, ReferenceLineAlignmentStatus.missing);
    expect(missing.asrLineIndex, isNull);
    expect(missing.similarity, 0);
    expect(missing.startTime, isNull);
    expect(missing.endTime, isNull);
    expect(result.missingReferenceIndices, [1]);
    expect(result.hasMissingReferences, isTrue);
    expect(result.unmatchedAsrIndices, isEmpty);
  });

  test('marks ASR hallucination lines as unmatched', () {
    final result = service.align(
      document: document([asr('第一句'), asr('啊啊啊乱识别'), asr('第二句')]),
      referenceLines: [reference('第一句'), reference('第二句')],
    );

    expect(result.entries, hasLength(2));
    expect(result.entries[0].asrLineIndex, 0);
    expect(result.entries[1].asrLineIndex, 2);
    expect(result.unmatchedAsrIndices, [1]);
    expect(result.asrLines[1].status, AsrLineAlignmentStatus.unmatched);
    expect(result.missingReferenceIndices, isEmpty);
  });

  test('ignores case, punctuation and full-width differences', () {
    final result = service.align(
      document: document([asr('Hello, World!'), asr('我们 ＡＢＣ １２３！')]),
      referenceLines: [reference('hello world'), reference('我们 abc 123')],
    );

    expect(result.entries.map((entry) => entry.status), [
      ReferenceLineAlignmentStatus.identical,
      ReferenceLineAlignmentStatus.identical,
    ]);
    expect(LyricAlignmentService.normalizeLine('ＡＢＣ，１２３。'), 'abc123');
  });

  test('uses reference timestamps and their own offset-free times', () {
    final result = service.align(
      document: document([
        asr('第一句', startMs: 1000, endMs: 5000),
        asr('第二句', startMs: 5000, endMs: 9000),
      ]),
      referenceLines: [
        reference('第一句', startMs: 30000, endMs: 34000),
        reference('第二句', startMs: 34000, endMs: 38000),
      ],
    );

    expect(result.entries[0].referenceHasTimestamp, isTrue);
    expect(result.entries[0].startTime, const Duration(seconds: 30));
    expect(result.entries[0].endTime, const Duration(seconds: 34));
    expect(result.entries[1].referenceHasTimestamp, isTrue);
    expect(result.entries[1].startTime, const Duration(seconds: 34));
    expect(result.entries[1].endTime, const Duration(seconds: 38));
    // Text is unchanged, so timing replacement is the only effect.
    expect(result.entries[1].status, ReferenceLineAlignmentStatus.identical);
  });

  test('falls back to ASR timing for partially timed references', () {
    final result = service.align(
      document: document([
        asr('第一句', startMs: 1000, endMs: 5000),
        asr('第二句', startMs: 5000, endMs: 9000),
      ]),
      referenceLines: [
        reference('第一句', startMs: 30000, endMs: 34000),
        reference('第二句'),
      ],
    );

    expect(result.entries[0].startTime, const Duration(seconds: 30));
    expect(result.entries[1].referenceHasTimestamp, isFalse);
    expect(result.entries[1].startTime, const Duration(seconds: 5));
    expect(result.entries[1].endTime, const Duration(seconds: 9));
  });

  test('skips empty reference lines and empty ASR lines', () {
    final result = service.align(
      document: document([asr('第一句'), asr(''), asr('第二句')]),
      referenceLines: [reference('第一句'), reference('，。！？'), reference('第二句')],
    );

    expect(result.entries, hasLength(2));
    expect(result.entries[0].referenceIndex, 0);
    expect(result.entries[0].asrLineIndex, 0);
    expect(result.entries[1].referenceIndex, 2);
    expect(result.entries[1].asrLineIndex, 2);
    expect(result.unmatchedAsrIndices, isEmpty);
    expect(result.missingReferenceIndices, isEmpty);
  });

  test('keeps repeated chorus lines in sequence order', () {
    final result = service.align(
      document: document([
        asr('A段'),
        asr('副歌第一句'),
        asr('副歌第二句'),
        asr('过渡句'),
        asr('不一样的内容'),
        asr('结尾句'),
      ]),
      referenceLines: [
        reference('A段'),
        reference('副歌第一句'),
        reference('副歌第二句'),
        reference('过渡句'),
        reference('副歌第二句'),
        reference('结尾句'),
      ],
    );

    // 第二次副歌在 ASR 丢失，不能被错配到第一次副歌。
    expect(result.missingReferenceIndices, [4]);
    expect(result.unmatchedAsrIndices, [4]);
    expect(result.entries.map((entry) => entry.asrLineIndex), [
      0,
      1,
      2,
      3,
      null,
      5,
    ]);
  });

  test('raises the bar when minimum pair similarity is strict', () {
    const strict = LyricAlignmentService(minimumPairSimilarity: 0.9);
    final result = strict.align(
      document: document([asr('月亮代表我的星')]),
      referenceLines: [reference('月亮代表我的心')],
    );

    expect(result.entries.single.status, ReferenceLineAlignmentStatus.missing);
    expect(result.asrLines.single.status, AsrLineAlignmentStatus.unmatched);
  });

  test('marks every reference line missing when the ASR draft is empty', () {
    final result = service.align(
      document: document(const []),
      referenceLines: [
        reference('第一句', startMs: 1000, endMs: 5000),
        reference('第二句'),
      ],
    );

    expect(result.entries, hasLength(2));
    expect(result.entries.map((entry) => entry.status), [
      ReferenceLineAlignmentStatus.missing,
      ReferenceLineAlignmentStatus.missing,
    ]);
    expect(result.entries[0].startTime, const Duration(seconds: 1));
    expect(result.entries[0].endTime, const Duration(seconds: 5));
    expect(result.entries[1].startTime, isNull);
    expect(result.asrLines, isEmpty);
  });

  test('marks every ASR line unmatched when there is no reference', () {
    final result = service.align(
      document: document([asr('第一句'), asr('第二句')]),
      referenceLines: const [],
    );

    expect(result.entries, isEmpty);
    expect(result.asrLines, hasLength(2));
    expect(result.unmatchedAsrIndices, [0, 1]);
    expect(
      result.asrLines.every(
        (line) => line.status == AsrLineAlignmentStatus.unmatched,
      ),
      isTrue,
    );
  });

  test('computes character-level similarity', () {
    expect(
      LyricAlignmentService.lineSimilarity('月亮代表我的心', '月亮代表我的星'),
      closeTo(6 / 7, 1e-9),
    );
    expect(
      LyricAlignmentService.lineSimilarity('Hello, World!', 'hello world'),
      1,
    );
    expect(LyricAlignmentService.lineSimilarity('完全不同的句子', 'another line'), 0);
  });
}
