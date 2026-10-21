import 'reference_lyric_line.dart';

/// 参考歌词输入：C2 对话框解析后交给对齐流程的完整数据。
///
/// [offset] 是已经叠加到 [lines] 时间戳上的总偏移（来自 LRC 的 `[offset:]`
/// 加上用户在对话框里填写的整体偏移），用于后续溯源。
class ReferenceLyricInput {
  final List<ReferenceLyricLine> lines;
  final bool timed;
  final String format;
  final Duration offset;
  final String? sourcePath;
  final String? title;
  final String? artist;

  /// 导入阶段发现的时间轴冲突（例如 LRC 重复/倒退时间戳），原样带给审核界面。
  final List<String> conflicts;

  /// 导入阶段对时间戳做的保守修复说明，展示在审核界面上，不静默丢弃。
  final List<String> warnings;

  const ReferenceLyricInput({
    required this.lines,
    required this.timed,
    required this.format,
    this.offset = Duration.zero,
    this.sourcePath,
    this.title,
    this.artist,
    this.conflicts = const [],
    this.warnings = const [],
  });

  bool get hasConflicts => conflicts.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;

  int get lineCount => lines.length;
}
