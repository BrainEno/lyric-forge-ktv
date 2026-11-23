import '../../player/domain/services/playback_session_service.dart';

/// What a global search result is (D-065), in the order groups are listed
/// when their best results score the same.
enum GlobalSearchKind { action, project, song, playlist, lyric }

extension GlobalSearchKindX on GlobalSearchKind {
  /// Group header in the results.
  String get label => switch (this) {
    GlobalSearchKind.action => '操作与页面',
    GlobalSearchKind.project => '工程',
    GlobalSearchKind.song => '歌曲',
    GlobalSearchKind.playlist => '歌单',
    GlobalSearchKind.lyric => '歌词里提到',
  };

  /// How many results of this kind are listed before "还有 N 个".
  int get limit => switch (this) {
    GlobalSearchKind.action => 6,
    GlobalSearchKind.project => 6,
    GlobalSearchKind.song => 8,
    GlobalSearchKind.playlist => 5,
    GlobalSearchKind.lyric => 6,
  };
}

/// What choosing a result does.
sealed class GlobalSearchTarget {
  const GlobalSearchTarget();
}

/// Opens a page.
final class OpenRouteTarget extends GlobalSearchTarget {
  const OpenRouteTarget(this.route);

  final String route;
}

/// Plays a library song; the second action adds it to the queue instead.
final class PlaySongTarget extends GlobalSearchTarget {
  const PlaySongTarget(this.item);

  final PlaybackItem item;
}

/// Opens a playlist; the second action plays it.
final class OpenPlaylistTarget extends GlobalSearchTarget {
  const OpenPlaylistTarget({
    required this.playlistId,
    required this.route,
    this.songs = const [],
  });

  final String playlistId;
  final String route;

  /// The playlist's playable songs, in order.
  final List<PlaybackItem> songs;
}

/// Opens the keyboard shortcut panel.
final class ShowShortcutsTarget extends GlobalSearchTarget {
  const ShowShortcutsTarget();
}

/// One searchable thing: a page or action, a project, a song or a playlist.
class GlobalSearchItem {
  const GlobalSearchItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.target,
    this.subtitle,
    this.keywords = const [],
    this.lyricLines = const [],
  });

  final GlobalSearchKind kind;

  /// Unique among the items of its [kind].
  final String id;
  final String title;
  final String? subtitle;

  /// Other words that find the item without being shown: file names,
  /// English names and pinyin for the pages.
  final List<String> keywords;

  /// A project's lyric lines: a query found only there lists the project
  /// under [GlobalSearchKind.lyric] with the line it was found in.
  final List<String> lyricLines;

  final GlobalSearchTarget target;
}

/// A result: an item, how well it matched, and for a lyric match the line.
class GlobalSearchHit {
  const GlobalSearchHit({
    required this.item,
    required this.kind,
    required this.score,
    this.lyricLine,
  });

  final GlobalSearchItem item;

  /// The group it is listed in: the item's own kind, or
  /// [GlobalSearchKind.lyric] when only its lyrics matched.
  final GlobalSearchKind kind;
  final int score;
  final String? lyricLine;

  /// What the row shows under the title.
  String? get detail => lyricLine ?? item.subtitle;
}

/// The results of one kind.
class GlobalSearchGroup {
  const GlobalSearchGroup({
    required this.kind,
    required this.hits,
    this.hidden = 0,
  });

  final GlobalSearchKind kind;
  final List<GlobalSearchHit> hits;

  /// Matches past the kind's [GlobalSearchKindX.limit].
  final int hidden;
}

/// Everything shown for one query, groups in display order.
class GlobalSearchResults {
  const GlobalSearchResults(this.groups);

  static const empty = GlobalSearchResults([]);

  final List<GlobalSearchGroup> groups;

  /// The rows in display order, for moving the selection with the arrows.
  List<GlobalSearchHit> get hits => [
    for (final group in groups) ...group.hits,
  ];

  bool get isEmpty => groups.every((group) => group.hits.isEmpty);
}
