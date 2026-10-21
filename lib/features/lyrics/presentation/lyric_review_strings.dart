/// Centralised user-visible strings for lyric review and line audition.
abstract final class LyricReviewStrings {
  static const String auditionPlayTooltip = '播放/继续本行试听';
  static const String auditionPauseTooltip = '暂停本行试听';
  static const String auditionInvalidStart =
      '这一行的有效开始时间或结束时间无效，无法试听。';
  static const String auditionErrorPrefix = '无法试听当前歌词行：';
  static const String loopCurrentLineLabel = '循环本行';
  static const String loopCurrentLineHelp =
      '打开后，本行播放到结束时间会回到试听起点；没有有效结束时间的行无法自动循环。';
  static const String loopCurrentLineEnabled = '已开启循环本行';
  static const String loopCurrentLineDisabled = '已关闭循环本行';
}
