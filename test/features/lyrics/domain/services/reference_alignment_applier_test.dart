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

  group('逐行显式采纳', () {
    LyricDocument twoLineDocument() {
      return buildDocument([
        const LyricLine(
          text: '月亮代表我的星',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
        ),
        const LyricLine(
          text: '第二句错',
          startTime: Duration(seconds: 5),
          endTime: Duration(seconds: 9),
        ),
      ]);
    }

    LyricAlignmentResult twoLineAlignment(LyricDocument document) {
      return alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(text: '月亮代表我的心'),
          ReferenceLyricLine(text: '第二句对'),
        ],
      );
    }

    test('只应用显式选中的行', () {
      final document = twoLineDocument();
      final alignment = twoLineAlignment(document);

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: {1},
      );

      expect(result.corrections, hasLength(1));
      expect(result.corrections.single.referenceIndex, 1);
      expect(result.document.lines[0].text, '月亮代表我的星');
      expect(result.document.lines[1].text, '第二句对');
      expect(result.skippedBySelectionIndices, [0]);
      expect(result.skippedLowConfidenceIndices, isEmpty);
    });

    test('显式选中可以采纳低于阈值的行', () {
      final document = twoLineDocument();
      final alignment = twoLineAlignment(document);
      final lowConfidenceEntry = alignment.entries[1];
      expect(lowConfidenceEntry.similarity, lessThan(0.8));

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: {lowConfidenceEntry.referenceIndex},
      );

      expect(result.document.lines[1].text, '第二句对');
      expect(result.skippedLowConfidenceIndices, isEmpty);
      expect(result.skippedBySelectionIndices, [0]);
    });

    test('显式选中仍受手动编辑保护', () {
      final document = twoLineDocument();
      final alignment = twoLineAlignment(document);

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: {0},
        protectedLineIndices: {0},
      );

      expect(result.corrections, isEmpty);
      expect(result.skippedManuallyEditedIndices, [0]);
      expect(result.skippedLowConfidenceIndices, [1]);
      expect(result.skippedBySelectionIndices, isEmpty);
      expect(result.document.lines[0].text, '月亮代表我的星');
    });

    test('未选中的低相似行记录为低置信', () {
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

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: const {},
      );

      expect(result.corrections, isEmpty);
      expect(result.skippedLowConfidenceIndices, [0]);
      expect(result.skippedBySelectionIndices, isEmpty);
    });

    test('采用时间轴时，未选中的文字行也更新时间', () {
      final document = twoLineDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: const [
          ReferenceLyricLine(
            text: '月亮代表我的心',
            startTime: Duration(seconds: 30),
            endTime: Duration(seconds: 34),
          ),
          ReferenceLyricLine(
            text: '第二句对',
            startTime: Duration(seconds: 34),
            endTime: Duration(seconds: 39),
          ),
        ],
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: {0},
        applyReferenceTiming: true,
      );

      expect(result.corrections, hasLength(1));
      expect(result.document.lines[0].text, '月亮代表我的心');
      expect(result.document.lines[0].startTime, const Duration(seconds: 30));
      expect(result.document.lines[1].text, '第二句错');
      expect(result.document.lines[1].startTime, const Duration(seconds: 34));
      expect(result.document.lines[1].endTime, const Duration(seconds: 39));
      expect(result.timingUpdatedCount, 2);
    });

    test('空显式集合只更新时间轴', () {
      final document = buildDocument([
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
        acceptedReferenceIndices: const {},
        applyReferenceTiming: true,
      );

      expect(result.corrections, isEmpty);
      expect(result.hasChanges, isTrue);
      expect(result.document.lines[0].startTime, const Duration(seconds: 30));
      expect(result.document.lines[1].endTime, const Duration(seconds: 39));
    });
  });

  group('漏行补全', () {
    LyricDocument buildCompletionDocument() {
      return buildDocument([
        const LyricLine(
          text: '第一句歌词',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        const LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ]);
    }

    const referenceLines = [
      ReferenceLyricLine(text: '第一句歌词'),
      ReferenceLyricLine(text: '第二句歌词'),
      ReferenceLyricLine(text: '第三句歌词'),
    ];

    test('显式采纳漏行时按推断位置和时间插入', () {
      final document = buildCompletionDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedMissingReferenceIndices: const {1},
      );

      expect(result.insertions, hasLength(1));
      final insertion = result.insertions.single;
      expect(insertion.referenceIndex, 1);
      expect(insertion.asrLineIndex, 1);
      expect(insertion.text, '第二句歌词');
      expect(insertion.startTime, const Duration(seconds: 4));
      expect(insertion.endTime, const Duration(seconds: 8));
      expect(result.insertedCount, 1);
      expect(result.hasChanges, isTrue);

      expect(result.document.lines, hasLength(3));
      expect(result.document.lines[0].text, '第一句歌词');
      expect(result.document.lines[1].text, '第二句歌词');
      expect(result.document.lines[1].confidence, 100);
      expect(result.document.lines[1].startTime, const Duration(seconds: 4));
      expect(result.document.lines[1].endTime, const Duration(seconds: 8));
      expect(result.document.lines[2].text, '第三句歌词');
      expect(result.document.lines[2].startTime, const Duration(seconds: 8));
    });

    test('不传漏行选择时保持旧行为，不插入', () {
      final document = buildCompletionDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      );

      final result = applier.apply(document: document, alignment: alignment);

      expect(result.insertions, isEmpty);
      expect(result.document.lines, hasLength(2));
      expect(result.hasChanges, isFalse);
      expect(result.missingReferenceCount, 1);
    });

    test('文字纠正与漏行补全同时生效且索引保持正确', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句错字',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        const LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: const {0},
        acceptedMissingReferenceIndices: const {1},
      );

      expect(result.corrections, hasLength(1));
      expect(result.corrections.single.asrLineIndex, 0);
      expect(result.insertions, hasLength(1));
      expect(result.document.lines[0].text, '第一句歌词');
      expect(result.document.lines[1].text, '第二句歌词');
      expect(result.document.lines[2].text, '第三句歌词');
    });

    test('只补漏行不选文字时也标记为有变化', () {
      final document = buildCompletionDocument();
      final alignment = alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      );

      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedReferenceIndices: const {},
        acceptedMissingReferenceIndices: const {1},
      );

      expect(result.corrections, isEmpty);
      expect(result.insertions, hasLength(1));
      expect(result.hasChanges, isTrue);
    });

    test('补行记录原始插入点，用于迁移手动编辑索引', () {
      final document = buildDocument([
        const LyricLine(
          text: '第一句歌词',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        const LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ]);
      final alignment = alignmentService.align(
        document: document,
        referenceLines: referenceLines,
      );

      // 补行应插到原始索引 1（即第二句）之前，并记录该原始插入点。
      final result = applier.apply(
        document: document,
        alignment: alignment,
        acceptedMissingReferenceIndices: const {1},
      );

      expect(result.insertions, hasLength(1));
      final insertion = result.insertions.single;
      expect(insertion.referenceIndex, 1);
      expect(insertion.insertBeforeAsrLineIndex, 1);
      expect(insertion.asrLineIndex, 1);
    });
  });
}
