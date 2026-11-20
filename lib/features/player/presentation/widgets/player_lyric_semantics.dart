import '../../../../core/widgets/app_tap_target.dart';

/// Where a line sits in the player's three-line KTV focus view.
enum PlayerFocusLyricRole { previous, current, next }

/// Screen-reader wording of the player's lyric lines (audit A-04).
///
/// A tap on a lyric line seeks there, but the rows were bare `InkWell`s: a
/// reader heard the start time and the text as two loose stops, never that a
/// tap jumps there, and the playing line and chorus lines were only an
/// accent colour and an icon.
abstract final class PlayerLyricSemantics {
  static const String seekHint = '跳到这一句';
  static const String chorusLabel = '副歌';
  static const String currentLabel = '正在播放';
  static const String emptyLineLabel = '空白行';

  /// A row of the scrolling lyric list,
  /// e.g. `00:12，月亮代表我的心，副歌，正在播放`.
  static String listRow({
    required String time,
    required String text,
    bool chorus = false,
    bool current = false,
  }) {
    return AppTapTarget.join([
      time,
      _text(text),
      if (chorus) chorusLabel,
      if (current) currentLabel,
    ]);
  }

  /// A line of the focus view, prefixed with where it sits,
  /// e.g. `下一句：你问我爱你有多深`.
  static String focusLine(PlayerFocusLyricRole role, String text) {
    return '${roleLabel(role)}：${_text(text)}';
  }

  static String roleLabel(PlayerFocusLyricRole role) => switch (role) {
    PlayerFocusLyricRole.previous => '上一句',
    PlayerFocusLyricRole.current => '当前句',
    PlayerFocusLyricRole.next => '下一句',
  };

  static String _text(String text) =>
      text.trim().isEmpty ? emptyLineLabel : text.trim();
}
