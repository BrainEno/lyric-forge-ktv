import '../../../project/domain/models/lyric_document.dart';

/// 一次"在播放位置插入歌词行"的计算结果。
class LyricLineInsertion {
  /// 新行在列表中的插入索引。
  final int index;

  /// 新行本身（文本为空，时间由播放位置和相邻行推导）。
  final LyricLine line;

  const LyricLineInsertion({required this.index, required this.line});
}

/// 纯计算的时间轴插入规则：不依赖 Flutter、播放器或工程状态。
///
/// 约定：
/// - 新行插入到第一行 `startTime > position` 之前，保证按开始时间有序；
/// - 新行结束时间取下一行的开始时间；没有下一行时取 `position + 5s`；
/// - 与下一行间隔不足 10ms 时强制 10ms，避免零长度或倒置区间；
/// - 不修改原有行（是否裁剪上一行结束时间由调用方决定）。
class LyricTimelineInsertionService {
  const LyricTimelineInsertionService();

  static const Duration minimumDuration = Duration(milliseconds: 10);
  static const Duration defaultDuration = Duration(seconds: 5);

  LyricLineInsertion insertAtPlayback({
    required List<LyricLine> lines,
    required Duration position,
  }) {
    final start = position.isNegative ? Duration.zero : position;

    var index = lines.indexWhere((line) => line.startTime > start);
    if (index < 0) index = lines.length;

    final nextStart = index < lines.length ? lines[index].startTime : null;
    var end = nextStart ?? start + defaultDuration;
    if (end - start < minimumDuration) {
      end = start + minimumDuration;
    }

    return LyricLineInsertion(
      index: index,
      line: LyricLine(text: '', startTime: start, endTime: end),
    );
  }
}
