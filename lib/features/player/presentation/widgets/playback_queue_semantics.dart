import '../../../../core/widgets/app_tap_target.dart';

/// Screen-reader wording of the playback queue panel (audit A-04).
///
/// A queue row was a bare `InkWell`: a reader heard the title, the source
/// and a 当前 badge as loose words, never the row's place in the queue or
/// that a tap plays it from there.
abstract final class PlaybackQueueSemantics {
  static const String playHint = '从这首开始播放';
  static const String currentLabel = '正在播放';

  /// A queue row, e.g. `第 3 首，晴天，周杰伦，正在播放`.
  static String row({
    required int position,
    required String title,
    required String source,
    required bool current,
  }) {
    return AppTapTarget.join([
      '第 $position 首',
      title.trim().isEmpty ? '未命名歌曲' : title,
      source,
      if (current) currentLabel,
    ]);
  }

  /// The remove button; removing the playing song also skips to the next.
  static String removeTooltip({required bool current}) =>
      current ? '从队列移除并播放下一首' : '从队列移除';
}
