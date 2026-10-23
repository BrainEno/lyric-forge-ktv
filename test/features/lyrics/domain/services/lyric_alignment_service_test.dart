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

  group('匹配阈值 vs 自动替换阈值', () {
    test('相似度在匹配阈值与自动替换阈值之间时标记为低置信度，不自动替换', () {
      // '第二句错' 与 '第二句对' 归一化后 4 字中 1 字不同，相似度 0.75：
      // 高于配对偏置 0.7 而低于默认自动替换阈值 0.8。
      final result = service.align(
        document: document([asr('第二句错')]),
        referenceLines: [reference('第二句对')],
      );

      final entry = result.entries.single;
      expect(entry.similarity, closeTo(0.75, 1e-9));
      expect(entry.status, ReferenceLineAlignmentStatus.lowConfidence);
      expect(
        result.asrLines.single.status,
        AsrLineAlignmentStatus.lowConfidence,
      );
    });

    test('相似度低于配对偏置的弱匹配输给两条 gap，归为漏行/多余行', () {
      // '今天天气真好' 与 '明天天气不错' 相似度 0.5，低于默认 matchBias 0.7；
      // 强行配对不如"跳过参考行 + 跳过 ASR 行"两条 gap，因此不再标为低置信。
      final result = service.align(
        document: document([asr('今天天气真好')]),
        referenceLines: [reference('明天天气不错')],
      );

      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.missing,
      );
      expect(result.asrLines.single.status, AsrLineAlignmentStatus.unmatched);
    });

    test('降低自动替换阈值后，低置信度匹配可被自动替换', () {
      final result = service.align(
        document: document([asr('第二句错')]),
        referenceLines: [reference('第二句对')],
        autoReplaceThreshold: 0.7,
      );

      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.replace,
      );
      expect(
        result.asrLines.single.status,
        AsrLineAlignmentStatus.toBeCorrected,
      );
    });

    test('匹配阈值严格时，相似度不足的行直接标记为漏行而非低置信度', () {
      const strict = LyricAlignmentService(minimumPairSimilarity: 0.9);
      final result = strict.align(
        document: document([asr('今天天气真好')]),
        referenceLines: [reference('明天天气不错')],
      );

      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.missing,
      );
      expect(result.asrLines.single.status, AsrLineAlignmentStatus.unmatched);
    });
  });

  group('歧义匹配状态', () {
    test('两条 ASR 行与同一参考行相似度接近时标记为歧义匹配', () {
      // 参考与两条 ASR 行都不完全相同，但相似度均为 0.8 且互为接近候选。
      final result = service.align(
        document: document([asr('第一句歌词a'), asr('第一句歌词b')]),
        referenceLines: [reference('第一句歌词')],
      );

      final entry = result.entries.single;
      expect(entry.similarity, greaterThanOrEqualTo(0.8));
      expect(entry.status, ReferenceLineAlignmentStatus.ambiguous);
      expect(entry.ambiguous, isTrue);
    });

    test('相似度差距大于歧义边际时不标记为歧义匹配', () {
      final result = service.align(
        document: document([asr('第一句歌词'), asr('完全不同的内容')]),
        referenceLines: [reference('第一句歌词内容')],
      );

      final entry = result.entries.single;
      expect(entry.ambiguous, isFalse);
      // 参考与第一条 ASR 行不完全相同，相似度低于自动替换阈值，应为低置信度。
      expect(entry.status, ReferenceLineAlignmentStatus.lowConfidence);
    });
  });

  group('结构性分行差异', () {
    test('detects one reference line split across consecutive ASR lines', () {
      final result = service.align(
        document: document([
          asr('今夜星光'),
          asr('照亮我的路'),
        ]),
        referenceLines: [reference('今夜星光照亮我的路')],
      );

      expect(result.structuralMismatches, hasLength(1));
      final mismatch = result.structuralMismatches.single;
      expect(mismatch.kind, StructuralAlignmentMismatchKind.mergedAsrLines);
      expect(mismatch.referenceIndices, [0]);
      expect(mismatch.asrLineIndices, [0, 1]);
      expect(mismatch.similarity, 1);
      expect(result.entries.single.structuralMismatch, isTrue);
      expect(result.asrLines.every((line) => line.structuralMismatch), isTrue);
    });

    test('detects multiple reference lines merged into one ASR line', () {
      final result = service.align(
        document: document([asr('今夜星光照亮我的路')]),
        referenceLines: [
          reference('今夜星光'),
          reference('照亮我的路'),
        ],
      );

      expect(result.structuralMismatches, hasLength(1));
      final mismatch = result.structuralMismatches.single;
      expect(mismatch.kind, StructuralAlignmentMismatchKind.splitAsrLine);
      expect(mismatch.referenceIndices, [0, 1]);
      expect(mismatch.asrLineIndices, [0]);
      expect(mismatch.similarity, 1);
      expect(result.entries.every((entry) => entry.structuralMismatch), isTrue);
      expect(result.asrLines.single.structuralMismatch, isTrue);
      expect(result.hasStructuralMismatches, isTrue);
    });

    test('keeps structural mismatch indices in original order around empty lines', () {
      final result = service.align(
        document: document([
          asr('今夜星光'),
          asr('照亮我的路'),
        ]),
        referenceLines: [
          reference('今夜星光照亮我的路'),
          reference('，。！？'),
        ],
      );

      expect(result.structuralMismatches, hasLength(1));
      expect(result.structuralMismatches.single.referenceIndices, [0]);
      expect(result.structuralMismatches.single.asrLineIndices, [0, 1]);
    });
  });

}
