import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/proofreading/project_proofread_evidence.dart';
import '../../domain/proofreading/independent_snapshot_comparison.dart';

/// Inspect the original engine outputs, not a proposal to change lyrics.
class ProjectAsrSnapshotDialog extends StatelessWidget {
  final ProjectProofreadEvidenceResult evidence;

  ProjectAsrSnapshotDialog({super.key, required this.evidence})
    : assert(evidence.status == ProjectProofreadEvidenceStatus.auditOnly);

  @override
  Widget build(BuildContext context) {
    final primary = evidence.primary!;
    final secondary = evidence.secondary!;
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        title: const Text('原始双引擎快照（只读）'),
        content: SizedBox(
          width: 640,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前歌词与原始主引擎稿不同，可能经过融合或编辑。以下是识别时的两份原稿，不代表当前歌词与第二引擎独立一致，也不保证准确。音频校验仅为时点检查。',
              ),
              const SizedBox(height: 8),
              Text('采集时间（UTC）：${evidence.capturedAtUtc!.toIso8601String()}'),
              const TabBar(isScrollable: true, tabs: [Tab(text: '原稿比较'), Tab(text: '主引擎原稿'), Tab(text: '第二引擎原稿')]),
              Expanded(
                child: TabBarView(
                  children: [
                    _SnapshotComparisonView(primary: primary, secondary: secondary),
                    _SnapshotTranscript(
                      engine: evidence.primaryEngine!,
                      document: primary,
                    ),
                    _SnapshotTranscript(
                      engine: evidence.secondaryEngine!,
                      document: secondary,
                    ),
                  ],
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
      ),
    );
  }
}

class _SnapshotTranscript extends StatelessWidget {
  final String engine;
  final LyricDocument document;

  const _SnapshotTranscript({required this.engine, required this.document});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: PageStorageKey(engine),
      itemCount: document.lines.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('引擎：$engine · 语言：${document.language}'),
          );
        }
        final line = document.lines[index - 1];
        return ListTile(
          title: Text(line.text),
          subtitle: Text(
            '第 $index 行 · ${_time(line.startTime)} – ${_time(line.endTime)} · '
            '${line.hasConfidenceScore ? '置信度 ${line.confidence}' : '置信度未知'}',
          ),
        );
      },
    );
  }

  static String _time(Duration time) {
    final ms = time.inMilliseconds;
    final minutes = ms ~/ 60000;
    final seconds = (ms ~/ 1000) % 60;
    final fraction = ms % 1000;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${fraction.toString().padLeft(3, '0')}';
  }
}

class _SnapshotComparisonView extends StatelessWidget {
  final LyricDocument primary;
  final LyricDocument secondary;

  const _SnapshotComparisonView({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    final comparison = const IndependentSnapshotComparison().compare(
      primary: primary,
      secondary: secondary,
    );
    if (comparison.limitExceeded) {
      return const Center(child: Text('快照超出安全比较限制；请分别查看两份原稿。'));
    }
    return ListView.builder(
      itemCount: comparison.rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('仅对时间有重叠且一对一的原稿行比较原文；分段歧义不判一致。行号属于各自原稿，不对应当前歌词。'),
          );
        }
        final row = comparison.rows[index - 1];
        final label = switch (row.kind) {
          SnapshotComparisonKind.exactText => '原文相同（不保证准确）',
          SnapshotComparisonKind.differentText => '原文不同',
          SnapshotComparisonKind.primaryOnly => '仅主引擎有此时间段',
          SnapshotComparisonKind.secondaryOnly => '仅第二引擎有此时间段',
          SnapshotComparisonKind.ambiguousOverlap => '重叠关系有歧义，请查看原稿',
        };
        return ListTile(
          title: Text(label),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.primary != null)
                Text('主稿第 ${row.primaryIndex! + 1} 行：${row.primary!.text}'),
              if (row.secondary != null)
                Text('第二稿第 ${row.secondaryIndex! + 1} 行：${row.secondary!.text}'),
            ],
          ),
        );
      },
    );
  }
}
