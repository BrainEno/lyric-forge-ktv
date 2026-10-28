import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_applier.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_provenance_builder.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const alignmentService = LyricAlignmentService();
  const applier = ReferenceAlignmentApplier();
  const markerService = LyricManualEditMarkerService();
  const provenanceBuilder = ReferenceAlignmentProvenanceBuilder();
  final appliedAt = DateTime.utc(2026, 10, 21, 12);

  LyricDocument buildDocument() {
    return const LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
          id: 'line-0',
        ),
        LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
          id: 'line-1',
        ),
        LyricLine(
          text: '月亮代表我的星',
          startTime: Duration(seconds: 12),
          endTime: Duration(seconds: 16),
          id: 'line-2',
        ),
      ],
    );
  }

  const referenceLines = [
    ReferenceLyricLine(text: '第一句歌词'),
    ReferenceLyricLine(text: '第二句歌词'),
    ReferenceLyricLine(text: '第三句歌词'),
    ReferenceLyricLine(text: '月亮代表我的心'),
  ];

  ReferenceLyricInput buildInput() => const ReferenceLyricInput(
    lines: referenceLines,
    timed: false,
    format: 'text',
  );

  Map<String, dynamic> buildMetadata({
    required ReferenceAlignmentApplyResult result,
    required LyricDocument appliedDocument,
  }) {
    return provenanceBuilder.build(
      appliedAt: appliedAt,
      input: buildInput(),
      minimumSimilarity: applier.minimumSimilarity,
      applyReferenceTiming: false,
      acceptedReferenceCount: 0,
      acceptedMissingReferenceCount: 1,
      overriddenManuallyEditedCount: 0,
      result: result,
      appliedDocument: appliedDocument,
    );
  }

  test('记录应用前索引基准与补行在应用后的最终位置', () {
    final document = buildDocument();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: referenceLines,
    );
    final result = applier.apply(
      document: document,
      alignment: alignment,
      acceptedMissingReferenceIndices: const {1},
    );
    final applied = markerService.assignMissingLineIds(result.document);

    final metadata = buildMetadata(result: result, appliedDocument: applied);

    expect(metadata['indexBase'], 'pre-application');

    // 补入行落在应用后文档的第 2 行，且带稳定标识。
    final insertion =
        (metadata['insertions'] as List).single as Map<String, dynamic>;
    expect(insertion['insertBeforeAsrLineIndex'], 1);
    expect(insertion['appliedLineIndex'], 1);
    expect(insertion['lineId'], applied.lines[1].id);
    expect(applied.lines[1].text, '第二句歌词');
    expect(insertion['referenceIndex'], 1);

    // 纠正行原本是第 3 行（原始索引 2），补行后落到应用后索引 3；
    // 溯源同时保留原始索引与稳定标识，不随补行漂移。
    final correction =
        (metadata['corrections'] as List).single as Map<String, dynamic>;
    expect(correction['asrLineIndex'], 2);
    expect(correction['lineId'], 'line-2');
    expect(applied.lines[3].id, 'line-2');
    expect(applied.lines[3].text, '月亮代表我的心');
  });

  test('被保护跳过的行以稳定标识记录，且映射到应用后的行', () {
    final document = buildDocument();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: referenceLines,
    );
    final result = applier.apply(
      document: document,
      alignment: alignment,
      acceptedMissingReferenceIndices: const {1},
      protectedLineIndices: const {2},
    );
    final applied = markerService.assignMissingLineIds(result.document);

    expect(result.skippedManuallyEditedIndices, [2]);
    expect(result.corrections, isEmpty);

    final metadata = buildMetadata(result: result, appliedDocument: applied);

    expect(metadata['skippedManuallyEditedLineIds'], ['line-2']);
    expect(metadata['skippedManuallyEditedCount'], 1);
    expect(metadata['appliedCorrectionCount'], 0);
    expect(metadata['insertedReferenceCount'], 1);
  });

  test('无补行时纠正行标识直接对应当前行', () {
    final document = buildDocument();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: referenceLines,
    );
    final result = applier.apply(document: document, alignment: alignment);
    final applied = markerService.assignMissingLineIds(result.document);

    final metadata = buildMetadata(result: result, appliedDocument: applied);
    final correction =
        (metadata['corrections'] as List).single as Map<String, dynamic>;

    expect(result.corrections.single.asrLineIndex, 2);
    expect(correction['lineId'], 'line-2');
    expect(metadata['insertions'], isEmpty);
    expect(metadata['indexBase'], 'pre-application');
  });
}
