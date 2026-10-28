import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_applier.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_provenance_builder.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const markers = LyricManualEditMarkerService();
  const alignmentService = LyricAlignmentService();
  const applier = ReferenceAlignmentApplier();

  test('保存重开工程后保留行标识、手工编辑标记与对齐保护', () async {
    final root = await Directory.systemTemp.createTemp('lyricforge-e4-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final repository = FileProjectRepository(rootDirectory: root);
    var project = await repository.createProject(name: 'E4 Persistence');

    // 编辑器会话：加载无标识文档 -> 补齐标识 -> 用户手动改第二行 -> 保存。
    const loaded = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '月亮代表我的星',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '第二句原词',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 8),
        ),
        LyricLine(
          text: '第三句原词很长',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ],
    );
    final withIds = markers.assignMissingLineIds(loaded);
    final manualLineId = withIds.lines[1].id!;
    final firstLineId = withIds.lines[0].id!;
    final thirdLineId = withIds.lines[2].id!;
    final sessionDocument = withIds.copyWith(
      lines: [
        withIds.lines[0],
        withIds.lines[1].copyWith(text: '第二句我改的词'),
        withIds.lines[2],
      ],
    );
    final markerIds = {manualLineId};
    final saved = sessionDocument.copyWith(
      metadata: markers.persist(sessionDocument, markerIds),
    );
    project = await repository.updateProject(
      project.copyWith(lyricDocument: saved),
    );

    // 真实重开：新仓库实例从磁盘读回工程。
    final reopenedRepository = FileProjectRepository(rootDirectory: root);
    final reopened = await reopenedRepository.getProjectById(project.id);
    final document = reopened!.lyricDocument!;

    expect(document.lines[0].id, firstLineId);
    expect(document.lines[1].id, manualLineId);
    expect(document.lines[2].id, thirdLineId);
    expect(document.lines[1].text, '第二句我改的词');

    final restoredMarkers = markers.restore(document);
    expect(restoredMarkers, markerIds);
    expect(markers.protectedIndices(document, restoredMarkers), {1});

    // 重开后再次运行参考对齐：手工编辑行保持跳过，其余行正常纠正。
    const referenceLines = [
      ReferenceLyricLine(text: '月亮代表我的心'),
      ReferenceLyricLine(text: '第二句我改的字'),
      ReferenceLyricLine(text: '第三句原词很常'),
    ];
    final alignment = alignmentService.align(
      document: document,
      referenceLines: referenceLines,
    );
    final result = applier.apply(
      document: document,
      alignment: alignment,
      protectedLineIndices: markers.protectedIndices(document, restoredMarkers),
    );

    expect(result.skippedManuallyEditedIndices, [1]);
    expect(result.document.lines[1].text, '第二句我改的词');
    expect(result.document.lines[0].text, '月亮代表我的心');
    expect(result.document.lines[2].text, '第三句原词很常');

    // 溯源记录同样基于稳定标识：应用前索引基准 + 纠正行/跳过行的 lineId。
    final applied = markers.assignMissingLineIds(result.document);
    final provenance = const ReferenceAlignmentProvenanceBuilder().build(
      appliedAt: DateTime.utc(2026, 10, 21, 12),
      input: const ReferenceLyricInput(
        lines: referenceLines,
        timed: false,
        format: 'text',
      ),
      minimumSimilarity: applier.minimumSimilarity,
      applyReferenceTiming: false,
      acceptedReferenceCount: 0,
      acceptedMissingReferenceCount: 0,
      overriddenManuallyEditedCount: 0,
      result: result,
      appliedDocument: applied,
    );

    expect(provenance['indexBase'], 'pre-application');
    expect(provenance['appliedCorrectionCount'], 2);
    expect(provenance['skippedManuallyEditedLineIds'], [manualLineId]);
    final correctedLineIds = [
      for (final correction in provenance['corrections'] as List)
        (correction as Map<String, dynamic>)['lineId'],
    ];
    expect(correctedLineIds, containsAll([firstLineId, thirdLineId]));
  });
}
