import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_applier.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// 可重复运行的歌词对齐回归样本测试集。
///
/// 样本覆盖：完全匹配、错别字（高相似度）、低置信度匹配、漏行、
/// 歧义匹配、多余识别行、中英混排、空行。重点断言：
/// - 高相似度错别字会被纠正（不漏报）；
/// - 低置信度与歧义匹配不会被错误自动采纳（不误报）；
/// - 漏行与多余识别行会被准确标记。
void main() {
  const alignmentService = LyricAlignmentService();
  const applier = ReferenceAlignmentApplier();

  LyricLine asr(String text, {int startMs = 0, int endMs = 4000}) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
  );

  ReferenceLyricLine ref(String text) => ReferenceLyricLine(text: text);

  group('歌词对齐回归样本', () {
    test('完全匹配：识别正确，无需纠正', () {
      final doc = LyricDocument(language: 'zh', lines: [asr('月亮代表我的心')]);
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('月亮代表我的心')],
      );

      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.identical,
      );
      // 自动模式下无需纠正。
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.corrections, isEmpty);
      expect(applied.skippedLowConfidenceIndices, isEmpty);
    });

    test('错别字高相似度：自动纠正，不漏报', () {
      final doc = LyricDocument(language: 'zh', lines: [asr('月亮代表我的星')]);
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('月亮代表我的心')],
      );

      final entry = result.entries.single;
      expect(entry.status, ReferenceLineAlignmentStatus.replace);
      expect(entry.similarity, greaterThanOrEqualTo(0.8));
      // 自动模式下会被纠正。
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.document.lines.single.text, '月亮代表我的心');
      expect(applied.corrections, hasLength(1));
    });

    test('低置信度匹配：不自动纠正，不误报', () {
      final doc = LyricDocument(language: 'zh', lines: [asr('今天天气真好')]);
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('明天天气不错')],
      );

      final entry = result.entries.single;
      expect(entry.status, ReferenceLineAlignmentStatus.lowConfidence);
      // 自动模式下不纠正，避免错误替换。
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.document.lines.single.text, '今天天气真好');
      expect(applied.corrections, isEmpty);
      expect(applied.skippedLowConfidenceIndices, [0]);
    });

    test('低置信度匹配：用户显式确认后可纠正', () {
      final doc = LyricDocument(language: 'zh', lines: [asr('今天天气真好')]);
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('明天天气不错')],
      );

      final entry = result.entries.single;
      final applied = applier.apply(
        document: doc,
        alignment: result,
        acceptedReferenceIndices: {entry.referenceIndex},
      );
      expect(applied.document.lines.single.text, '明天天气不错');
      expect(applied.corrections, hasLength(1));
    });

    test('漏行：ASR 未识别的参考行被标记 missing，不自动插入', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr('第一句歌词'), asr('第三句歌词')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('第一句歌词'), ref('第二句歌词'), ref('第三句歌词')],
      );

      expect(result.missingReferenceIndices, [1]);
      expect(result.hasMissingReferences, isTrue);
      // 不自动插入漏行。
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.insertions, isEmpty);
      expect(applied.document.lines, hasLength(2));
    });

    test('歧义匹配：两条 ASR 行与参考行相似度接近，标记 ambiguous', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr('第一句歌词a'), asr('第一句歌词b')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('第一句歌词')],
      );

      final entry = result.entries.single;
      expect(entry.status, ReferenceLineAlignmentStatus.ambiguous);
      expect(entry.ambiguous, isTrue);
      // 自动模式下不纠正。
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.corrections, isEmpty);
    });

    test('多余识别行：ASR 多出的行标记 unmatched，保留原样', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr('第一句歌词'), asr('呃呃呃幻觉'), asr('第二句歌词')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('第一句歌词'), ref('第二句歌词')],
      );

      expect(result.unmatchedAsrIndices, [1]);
      expect(result.hasUnmatchedAsrLines, isTrue);
      final applied = applier.apply(document: doc, alignment: result);
      expect(applied.document.lines, hasLength(3));
      expect(applied.document.lines[1].text, '呃呃呃幻觉');
    });

    test('中英混排：归一化后匹配，标点与全半角不影响', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr('Hello, World! 你好')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('hello world 你好')],
      );

      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.identical,
      );
    });

    test('空行不参与对齐，不影响结果', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr(''), asr('第一句歌词'), asr('')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('，。！？'), ref('第一句歌词')],
      );

      expect(result.entries, hasLength(1));
      expect(
        result.entries.single.status,
        ReferenceLineAlignmentStatus.identical,
      );
    });

    test('错误自动采纳统计：低置信/歧义行在自动模式下采纳数为 0', () {
      final doc = LyricDocument(
        language: 'zh',
        lines: [asr('今天天气真好'), asr('第一句歌词a'), asr('第一句歌词b')],
      );
      final result = alignmentService.align(
        document: doc,
        referenceLines: [ref('明天天气不错'), ref('第一句歌词')],
      );

      final applied = applier.apply(document: doc, alignment: result);
      // 低置信与歧义行均不应在自动模式下被采纳。
      expect(applied.corrections, isEmpty);
      expect(applied.skippedLowConfidenceIndices, isNotEmpty);
    });
  });
}
