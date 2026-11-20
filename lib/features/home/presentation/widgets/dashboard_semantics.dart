import '../../../../core/widgets/app_tap_target.dart';
import '../../../project/domain/models/project_manifest.dart';

/// Screen-reader wording of the dashboard's cards (audit A-04).
///
/// The cards were bare `InkWell`s: a reader heard the title and a muted
/// second line with no hint that a tap plays or opens anything. A project's
/// status was only the colour of a 9 px dot, and the playing song in the
/// queue preview only an accent colour and an icon.
abstract final class DashboardSemantics {
  static const String playHint = '播放';
  static const String openProjectHint = '打开歌词工程';
  static const String playNowHint = '从这首开始播放';

  /// What the status dot's colour means.
  static String statusLabel(ProjectStatus status) => switch (status) {
    ProjectStatus.draft => '草稿',
    ProjectStatus.importing => '导入中',
    ProjectStatus.processing => '处理中',
    ProjectStatus.transcribing => '识别中',
    ProjectStatus.editing => '待校对',
    ProjectStatus.ready => '就绪',
    ProjectStatus.error => '需要处理',
  };

  /// A card of 最近听过: title, artist or when it was played.
  static String listeningCard({
    required String title,
    required String? artist,
    required String playedAt,
  }) {
    final hasArtist = artist?.trim().isNotEmpty == true;
    return AppTapTarget.join([
      _title(title),
      hasArtist ? artist : null,
      '$playedAt播放',
    ]);
  }

  /// A project card: name, artist, status, lyric count, stage and progress,
  /// e.g. `晴天，周杰伦，待校对，32 行歌词，歌词已识别，进度 67%`.
  static String projectCard({
    required String name,
    required String? artist,
    required ProjectStatus status,
    required int lyricLines,
    required String stage,
    required double progress,
  }) {
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return AppTapTarget.join([
      _title(name),
      artist,
      statusLabel(status),
      lyricLines > 0 ? '$lyricLines 行歌词' : '待生成歌词',
      stage,
      '进度 $percent%',
    ]);
  }

  /// A song in the queue preview; the current one says it is playing.
  static String queueRow({
    required String title,
    required String source,
    required bool current,
  }) {
    return AppTapTarget.join([
      _title(title),
      source,
      if (current) '正在播放',
    ]);
  }

  static String _title(String title) =>
      title.trim().isEmpty ? '未命名歌曲' : title;
}
