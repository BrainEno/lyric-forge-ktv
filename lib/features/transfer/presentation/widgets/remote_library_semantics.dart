import '../../../../core/widgets/app_tap_target.dart';

/// Where a desktop-library song stands on the phone, as the tile's download
/// button shows it.
enum RemoteTrackDownloadState {
  /// Not on the phone and not queued.
  none,
  queued,
  transferring,
  failed,

  /// The download finished but the file is gone again.
  stale,
  downloaded,
}

/// Screen-reader wording of the phone's view of the desktop music library
/// (audit A-04).
///
/// The track tiles and artist/album cards were bare `InkWell`s: a reader
/// heard the title and a `·`-joined line as loose words, never that a tap
/// plays or opens anything. Whether a song was already on the phone was only
/// the download button's icon, and the lyrics note only an icon.
abstract final class RemoteLibrarySemantics {
  static const String playHint = '播放';
  static const String openArtistHint = '打开歌手';
  static const String openAlbumHint = '打开专辑';
  static const String lyricsLabel = '有歌词';

  /// The download button's tooltip, which is also its action's name.
  static String downloadTooltip(RemoteTrackDownloadState state) {
    return switch (state) {
      RemoteTrackDownloadState.downloaded => '已下载到手机',
      RemoteTrackDownloadState.failed ||
      RemoteTrackDownloadState.stale => '重新下载',
      RemoteTrackDownloadState.queued => '等待下载',
      RemoteTrackDownloadState.transferring => '正在下载',
      RemoteTrackDownloadState.none => '下载到手机',
    };
  }

  /// Whether the download button does anything in [state].
  static bool canDownload(RemoteTrackDownloadState state) {
    return switch (state) {
      RemoteTrackDownloadState.none ||
      RemoteTrackDownloadState.failed ||
      RemoteTrackDownloadState.stale => true,
      RemoteTrackDownloadState.queued ||
      RemoteTrackDownloadState.transferring ||
      RemoteTrackDownloadState.downloaded => false,
    };
  }

  /// The download state as part of the tile's label; null for a song that
  /// is simply not on the phone.
  static String? downloadStatus(
    RemoteTrackDownloadState state, {
    double? fraction,
    String? error,
  }) {
    return switch (state) {
      RemoteTrackDownloadState.none => null,
      RemoteTrackDownloadState.downloaded => '已下载到手机',
      RemoteTrackDownloadState.queued => '等待下载',
      RemoteTrackDownloadState.transferring =>
        fraction == null
            ? '正在下载'
            : '正在下载 ${(fraction.clamp(0.0, 1.0) * 100).round()}%',
      RemoteTrackDownloadState.failed =>
        error?.trim().isNotEmpty == true ? '下载失败：${error!.trim()}' : '下载失败',
      RemoteTrackDownloadState.stale => '本地文件已不存在，可重新下载',
    };
  }

  /// A track tile, e.g. `晴天，周杰伦，叶惠美，FLAC，有歌词，已下载到手机`.
  static String trackTile({
    required String title,
    required String? artist,
    required String? album,
    required String format,
    required bool hasLyrics,
    required RemoteTrackDownloadState state,
    double? fraction,
    String? error,
  }) {
    return AppTapTarget.join([
      title.trim().isEmpty ? '未命名歌曲' : title,
      artist,
      album,
      format.toUpperCase(),
      if (hasLyrics) lyricsLabel,
      downloadStatus(state, fraction: fraction, error: error),
    ]);
  }

  /// An artist or album card, e.g. `周杰伦，12 首`.
  static String groupCard({required String name, required int count}) {
    return AppTapTarget.join([name.trim().isEmpty ? '未知' : name, '$count 首']);
  }
}
