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

  const ReferenceLyricInput({
    required this.lines,
    required this.timed,
    required this.format,
    this.offset = Duration.zero,
    this.sourcePath,
    this.title,
    this.artist,
  });

  int get lineCount => lines.length;
}
