import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_batch_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_timeline_completion_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const alignmentService = LyricAlignmentService();
  const selector = ReferenceAlignmentBatchSelector();
  const completionService = ReferenceTimelineCompletionService();

  LyricLine asr(String text, {int startMs = 0, int endMs = 4000}) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
  );

  ReferenceAlignmentBatchSelection select({
    required LyricDocument document,
    required List<ReferenceLyricLine> referenceLines,
    Set<int> protectedLineIndices = const {},
  }) {
    final alignment = alignmentService.align(
      document: document,
      referenceLines: referenceLines,
    );
    return selector.select(
      alignment: alignment,
      completionPlan: completionService.buildPlan(
        document: document,
        alignment: alignment,
      ),
      minimumSimilarity: LyricAlignmentService.defaultAutoReplaceThreshold,
      protectedLineIndices: protectedLineIndices,
    );
  }

  test('歧义匹配即使相似度达标也不进入安全批量', () {
    final selection = select(
      document: LyricDocument(
        language: 'zh',
        lines: [asr('第一句歌词a'), asr('第一句歌词b')],
      ),
      referenceLines: const [ReferenceLyricLine(text: '第一句歌词')],
    );

    expect(selection.safeReferenceIndices, isEmpty);
    expect(selection.uncertainReferenceIndices, {0});
  });

  test('低置信匹配进入需确认组，高置信错字进入安全组', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [asr('月亮代表我的星'), asr('第二句错')],
    );
    final selection = select(
      document: document,
      referenceLines: const [
        ReferenceLyricLine(text: '月亮代表我的心'),
        ReferenceLyricLine(text: '第二句对'),
      ],
    );

    expect(selection.safeReferenceIndices, {0});
    expect(selection.uncertainReferenceIndices, {1});
  });

  test('手动编辑保护行不进入安全批量', () {
    final selection = select(
      document: LyricDocument(language: 'zh', lines: [asr('月亮代表我的星')]),
      referenceLines: const [ReferenceLyricLine(text: '月亮代表我的心')],
      protectedLineIndices: const {0},
    );

    expect(selection.safeReferenceIndices, isEmpty);
    expect(selection.uncertainReferenceIndices, {0});
  });

  test('结构差异行进入需确认组', () {
    // ASR 把一行拆成两行；参考只有一行，检测到一对多结构差异。
    final document = LyricDocument(
      language: 'zh',
      lines: [asr('第一句'), asr('歌词内容')],
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: const [ReferenceLyricLine(text: '第一句歌词内容')],
    );

    final selection = selector.select(
      alignment: alignment,
      completionPlan: completionService.buildPlan(
        document: document,
        alignment: alignment,
      ),
      minimumSimilarity: LyricAlignmentService.defaultAutoReplaceThreshold,
    );

    expect(alignment.structuralMismatches, isNotEmpty);
    expect(alignment.entries.single.structuralMismatch, isTrue);
    expect(selection.safeReferenceIndices, isEmpty);
    expect(selection.uncertainReferenceIndices, isEmpty);
    expect(selection.safeMissingReferenceIndices, isEmpty);
    expect(selection.uncertainMissingReferenceIndices, {0});
  });

  test('漏行按插入计划分为可补全与需确认', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        asr('第一句歌词', startMs: 0, endMs: 4000),
        asr('第三句歌词', startMs: 8000, endMs: 12000),
      ],
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: const [
        ReferenceLyricLine(text: '第一句歌词'),
        ReferenceLyricLine(text: '第二句歌词'),
        ReferenceLyricLine(text: '第三句歌词'),
      ],
    );
    final plan = completionService.buildPlan(
      document: document,
      alignment: alignment,
    );
    final selection = selector.select(
      alignment: alignment,
      completionPlan: plan,
      minimumSimilarity: LyricAlignmentService.defaultAutoReplaceThreshold,
    );

    expect(selection.safeMissingReferenceIndices, {1});
    expect(selection.uncertainMissingReferenceIndices, isEmpty);
  });
}
