import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_applier.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const alignmentService = LyricAlignmentService();
  const applier = ReferenceAlignmentApplier();

  LyricDocument buildDocument(List<LyricLine> lines) {
    return LyricDocument(language: 'zh', lines: lines);
  }

  group('文本纠正', () {
    test('高相似度错字被纠正，时间戳保持不变', () {
      final document = buildDocument([
        const LyricLine(
          text: '月亮代表我的星',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
          confidence: 42,
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.corrections, hasLength(1));
      expect(result.corrections.single.asrLineIndex, 0);
      expect(result.corrections.single.referenceIndex, 0);
      expect(result.corrections.single.previousText, '月亮代表我的星');
      expect(result.corrections.single.newText, '月亮代表我的心');
      expect(result.document.lines.single.text, '月亮代表我的心');
      expect(result.document.lines.single.confidence, 100);
      expect(
        result.document.lines.single.startTime,
        const Duration(seconds: 1),
      );
      expect(result.document.lines.single.endTime, const Duration(seconds: 5));
      expect(result.hasChanges, isTrue);
      expect(result.timingUpdatedCount, 0);
      expect(result.identicalCount, 0);
      expect(result.missingReferenceCount, 0);
      expect(result.unmatchedAsrCount, 0);
      // 输入文档保持不变，由调用方决定是否写回。
      expect(document.lines.single.text, '月亮代表我的星');
    });

    test('纠正时保留副歌标记', () {
      final document = buildDocument([
        const LyricLine(
          text: '月亮代表我的星',
          startTime: Duration.zero,
          endTime: Duration(seconds: 5),
          isChorus: true,
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.document.lines.single.isChorus, isTrue);
    });

    test('低于阈值的相似度不会自动纠正', () {
      final document = buildDocument([
        const LyricLine(
          text: '今天天气真好',
          startTime: Duration.zero,
          endTime: Duration(seconds: 3),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '明天天气不错')],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.corrections, isEmpty);
      expect(result.skippedLowConfidenceIndices, [0]);
      expect(result.document.lines.single.text, '今天天气真好');
      expect(result.hasChanges, isFalse);
    });

    test('可以按需收紧阈值', () {
      final document = buildDocument([
        const LyricLine(
          text: '月亮代表我的星',
          startTime: Duration.zero,
          endTime: Duration(seconds: 5),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      );

      final result = const ReferenceAlignmentApplier(
        minimumSimilarity: 0.9,
      ).apply(document: document, alignment: alignment);

      expect(result.corrections, isEmpty);
      expect(result.skippedLowConfidenceIndices, [0]);
    });

    test('本次手动编辑过的行被跳过并记录', () {
      final document = buildDocument([
        const LyricLine(
          text: '月亮代表我的星',
          startTime: Duration.zero,
          endTime: Duration(seconds: 5),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        protectedLineIndices: {0},
      );

      expect(result.corrections, isEmpty);
      expect(result.skippedManuallyEditedIndices, [0]);
      expect(result.document.lines.single.text, '月亮代表我的星');
    });

    test('完全一致的行不做任何改动', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '第一句！')],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.corrections, isEmpty);
      expect(result.identicalCount, 1);
      expect(result.document.lines.single.text, '第一句');
      expect(
        result.document.lines.single.startTime,
        const Duration(seconds: 1),
      );
      expect(result.hasChanges, isFalse);
    });

    test('参考漏行不会被自动插入', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句',
          startTime: Duration.zero,
          endTime: Duration(seconds: 3),
        ),
        const LyricLine(
          text: '第三句',
          startTime: Duration(seconds: 3),
          endTime: Duration(seconds: 6),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(text: '第一句'),
          ReferenceLyricLine(text: '呜呼哀哉'),
          ReferenceLyricLine(text: '第三句'),
        ],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(alignment.missingReferenceIndices, [1]);
      expect(result.missingReferenceCount, 1);
      expect(result.document.lines, hasLength(2));
    });

    test('多余的 ASR 行保持原样', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句',
          startTime: Duration.zero,
          endTime: Duration(seconds: 3),
        ),
        const LyricLine(
          text: '呃呵呵',
          startTime: Duration(seconds: 3),
          endTime: Duration(seconds: 6),
        ),
        const LyricLine(
          text: '第二句',
          startTime: Duration(seconds: 6),
          endTime: Duration(seconds: 9),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(text: '第一句'),
          ReferenceLyricLine(text: '第二句'),
        ],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.unmatchedAsrCount, 1);
      expect(result.document.lines, hasLength(3));
      expect(result.document.lines[1].text, '呃呵呵');
      expect(result.document.lines[1].startTime, const Duration(seconds: 3));
    });

    test('保留语言与 metadata', () {
      final document = LyricDocument(
        language: 'ja',
        lines: [
          const LyricLine(
            text: '月亮代表我的星',
            startTime: Duration.zero,
            endTime: Duration(seconds: 5),
          ),
        ],
        globalOffset: const Duration(milliseconds: 200),
        metadata: const {'source': 'whisper'},
      );
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.document.language, 'ja');
      expect(result.document.globalOffset, const Duration(milliseconds: 200));
      expect(result.document.metadata['source'], 'whisper');
    });
  });

  group('采用参考时间轴', () {
    LyricDocument timedDocument() {
      return buildDocument([
        const LyricLine(
          text: '第一句',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
        ),
        const LyricLine(
          text: '第二句',
          startTime: Duration(seconds: 5),
          endTime: Duration(seconds: 9),
        ),
      ]);
    }

    test('一一对应的带时间戳参考会替换全部行时间', () {
      final document = timedDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(
            text: '第一句',
            startTime: Duration(seconds: 30),
            endTime: Duration(seconds: 34),
          ),
          ReferenceLyricLine(
            text: '第二句',
            startTime: Duration(seconds: 34),
            endTime: Duration(seconds: 39),
          ),
        ],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        applyReferenceTiming: true,
      );

      expect(result.corrections, isEmpty);
      expect(result.timingUpdatedCount, 2);
      expect(result.hasChanges, isTrue);
      expect(result.document.lines[0].startTime, const Duration(seconds: 30));
      expect(result.document.lines[0].endTime, const Duration(seconds: 34));
      expect(result.document.lines[1].startTime, const Duration(seconds: 34));
      expect(result.document.lines[1].endTime, const Duration(seconds: 39));
    });

    test('默认不替换时间轴', () {
      final document = timedDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(
            text: '第一句',
            startTime: Duration(seconds: 30),
            endTime: Duration(seconds: 34),
          ),
          ReferenceLyricLine(
            text: '第二句',
            startTime: Duration(seconds: 34),
            endTime: Duration(seconds: 39),
          ),
        ],
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.timingUpdatedCount, 0);
      expect(result.hasChanges, isFalse);
      expect(result.document.lines[0].startTime, const Duration(seconds: 1));
      expect(result.document.lines[1].endTime, const Duration(seconds: 9));
    });

    test('参考行缺结束时间时由下一行开始时间推导', () {
      final document = timedDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(text: '第一句', startTime: Duration(seconds: 30)),
          ReferenceLyricLine(text: '第二句', startTime: Duration(seconds: 34)),
        ],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        applyReferenceTiming: true,
      );

      expect(result.document.lines[0].endTime, const Duration(seconds: 34));
      expect(result.document.lines[1].endTime, const Duration(seconds: 39));
    });

    test('结束时间早于开始时间时向后推导，末行补 5 秒', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句',
          startTime: Duration.zero,
          endTime: Duration(seconds: 5),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(
            text: '第一句',
            startTime: Duration(seconds: 30),
            endTime: Duration(seconds: 20),
          ),
        ],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        applyReferenceTiming: true,
      );

      expect(
        result.document.lines.single.startTime,
        const Duration(seconds: 30),
      );
      expect(result.document.lines.single.endTime, const Duration(seconds: 35));
    });

    test('手动编辑过的行不参与时间轴替换', () {
      final document = timedDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(
            text: '第一句',
            startTime: Duration(seconds: 30),
            endTime: Duration(seconds: 34),
          ),
          ReferenceLyricLine(
            text: '第二句',
            startTime: Duration(seconds: 34),
            endTime: Duration(seconds: 39),
          ),
        ],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        applyReferenceTiming: true,
        protectedLineIndices: {1},
      );

      expect(result.timingUpdatedCount, 1);
      expect(result.document.lines[0].startTime, const Duration(seconds: 30));
      expect(result.document.lines[1].startTime, const Duration(seconds: 5));
    });
  });
}
