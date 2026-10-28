/// 用户粘贴/导入的参考歌词行。
///
/// 纯文本参考只有 [text]；LRC 等带时间戳的参考行会带 [startTime]/[endTime]。
/// 时间戳是否存在按行判断，允许部分行带时间（例如手动补齐的段落）。
class ReferenceLyricLine {
  final String text;
  final Duration? startTime;
  final Duration? endTime;

  const ReferenceLyricLine({required this.text, this.startTime, this.endTime});

  bool get hasTimestamp => startTime != null;
}
