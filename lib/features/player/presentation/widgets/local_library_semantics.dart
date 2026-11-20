import '../../../../core/widgets/app_tap_target.dart';

/// Screen-reader wording of the local library's cards (audit A-04).
///
/// The artist, album, playlist and song cards were bare `InkWell`s: a reader
/// heard the title and a `·`-joined second line as loose words, never what a
/// tap opens. An unavailable song was only a red border and a muted line,
/// and the card's ⋯ menu a separate stop with a generic name.
abstract final class LocalLibrarySemantics {
  static const String openArtistHint = '打开歌手';
  static const String openAlbumHint = '打开专辑';
  static const String openPlaylistHint = '打开播放列表';
  static const String playHint = '播放';
  static const String unavailableLabel = '文件不可用';

  /// Turns a visible `A · B · C` line into spoken `A，B，C`.
  static String spoken(String dotted) => AppTapTarget.join(dotted.split(' · '));

  /// An artist or album card: title, then the counts line,
  /// e.g. `周杰伦，12 首，3 张专辑`.
  static String catalogCard({required String title, required String detail}) {
    return AppTapTarget.join([_title(title), spoken(detail)]);
  }

  /// An album in an artist's 专辑 shelf, e.g. `叶惠美，11 首`.
  static String miniAlbum({required String title, required int songs}) {
    return AppTapTarget.join([_title(title), '$songs 首']);
  }

  /// A playlist card, e.g. `通勤，24 首歌曲，2 首不可用`.
  static String playlistCard({
    required String name,
    required int songs,
    required int missing,
  }) {
    return AppTapTarget.join([
      _title(name),
      '$songs 首歌曲',
      if (missing > 0) '$missing 首不可用',
    ]);
  }

  /// A song card of the explorer grid: title, artist (or 文件不可用), then
  /// the track number, format, edited and lyrics notes.
  static String songCard({
    required String title,
    required String? artist,
    required bool playable,
    required Iterable<String> details,
  }) {
    return AppTapTarget.join([
      _title(title),
      playable ? (artist?.trim().isNotEmpty == true ? artist : '本地音乐') : null,
      if (!playable) unavailableLabel,
      ...details.map(spoken),
    ]);
  }

  static String _title(String title) =>
      title.trim().isEmpty ? '未命名' : title.trim();
}
