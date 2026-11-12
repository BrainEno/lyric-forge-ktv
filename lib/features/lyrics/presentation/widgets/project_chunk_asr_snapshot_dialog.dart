import 'package:flutter/material.dart';

import '../../domain/proofreading/project_proofread_evidence.dart';
import 'project_asr_snapshot_dialog.dart';

/// An index of verified original chunk pairs. No action mutates the draft.
class ProjectChunkAsrSnapshotDialog extends StatelessWidget {
  final List<ProjectProofreadChunk> chunks;

  const ProjectChunkAsrSnapshotDialog({super.key, required this.chunks})
    : assert(chunks.length > 0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分片原始双引擎快照（只读）'),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每个分片是独立识别任务，重叠区可能重复。请选择分片查看两份原稿；不比较当前歌词、不自动采纳，也不保证准确。音源校验仅为时点检查。',
            ),
            const SizedBox(height: 8),
            Text('共 ${chunks.length} 个分片，时间为完整音源的绝对时间。'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('chunk_snapshot_list'),
                itemCount: chunks.length,
                itemBuilder: (context, index) {
                  final chunk = chunks[index];
                  return ListTile(
                    key: ValueKey('chunk_snapshot_$index'),
                    title: Text('分片 ${chunk.index + 1}'),
                    subtitle: Text(
                      '${_time(chunk.start)} – ${_time(chunk.end)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => ProjectAsrSnapshotDialog(
                        chunkIndex: chunk.index,
                        evidence: ProjectProofreadEvidenceResult.auditOnly(
                          primary: chunk.primary,
                          primaryEngine: chunk.primaryEngine,
                          secondary: chunk.secondary,
                          secondaryEngine: chunk.secondaryEngine,
                          capturedAtUtc: chunk.capturedAtUtc,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  static String _time(Duration duration) {
    final ms = duration.inMilliseconds;
    return '${(ms ~/ 60000).toString().padLeft(2, '0')}:'
        '${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.'
        '${(ms % 1000).toString().padLeft(3, '0')}';
  }
}
