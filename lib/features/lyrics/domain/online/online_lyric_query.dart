import 'song_tags.dart';

/// What is sent to the lyric sites: a cleaned song title, the artist when
/// known, and the recording length to tell versions apart.
class OnlineLyricQuery {
  final String title;
  final String artist;
  final Duration? duration;

  const OnlineLyricQuery({
    required this.title,
    this.artist = '',
    this.duration,
  });

  /// Builds the query from a project's name, artist and audio length.
  ///
  /// Project names are often file names ("03. 周杰伦 - 晴天 (Live) [MV].mp3"),
  /// so the extension, a leading track number and bracketed extras are
  /// removed. Without an artist, an "A - B" name is read as "artist - title",
  /// the usual download naming; the keyword sources search both words anyway,
  /// so the order matters little.
  factory OnlineLyricQuery.fromProject({
    required String name,
    String? artist,
    Duration? duration,
  }) {
    var title = cleanTitle(name);
    var resolvedArtist = cleanArtist(artist ?? '');
    if (resolvedArtist.isEmpty) {
      final match = _artistTitle.firstMatch(title);
      if (match != null) {
        resolvedArtist = cleanArtist(match.group(1)!);
        title = cleanTitle(match.group(2)!);
      }
    } else {
      // "歌手 - 歌名" names are kept even when the artist is known.
      final match = _artistTitle.firstMatch(title);
      if (match != null) {
        final left = cleanArtist(match.group(1)!);
        final right = cleanTitle(match.group(2)!);
        if (_sameText(left, resolvedArtist)) {
          title = right;
        } else if (_sameText(right, resolvedArtist)) {
          title = cleanTitle(match.group(1)!);
        }
      }
    }
    return OnlineLyricQuery(
      title: title,
      artist: resolvedArtist,
      duration: duration == null || duration <= Duration.zero ? null : duration,
    );
  }

  /// The searches to try for a project, best first (D-055).
  ///
  /// The project name comes first unless it is a placeholder such as a
  /// recorder's file name ([isPlaceholderName]); then the title from the
  /// audio file's [tags] is tried. A missing artist is filled from the tags.
  /// Duplicates are dropped and unsearchable queries left out, so the list
  /// can be empty only when neither the name nor the tags name a song.
  static List<OnlineLyricQuery> candidatesFor({
    required String name,
    String? artist,
    Duration? duration,
    SongTags? tags,
  }) {
    final length = duration != null && duration > Duration.zero
        ? duration
        : tags?.duration;
    final fromName = OnlineLyricQuery.fromProject(
      name: name,
      artist: artist,
      duration: length,
    );
    final tagArtist = cleanArtist(tags?.artist ?? '');
    final named = fromName.artist.isEmpty && tagArtist.isNotEmpty
        ? fromName.copyWith(artist: tagArtist)
        : fromName;
    OnlineLyricQuery? fromTags;
    // A tag title that is itself a placeholder ("Track 01") adds nothing.
    if (tags != null && tags.hasTitle && !isPlaceholderName(tags.title!)) {
      final explicitArtist = cleanArtist(artist ?? '');
      fromTags = OnlineLyricQuery.fromProject(
        name: tags.title!,
        artist: explicitArtist.isNotEmpty
            ? explicitArtist
            : tagArtist.isNotEmpty
            ? tagArtist
            : named.artist,
        duration: length,
      );
    }
    final placeholder = isPlaceholderName(name);
    final ordered = [
      if (!placeholder) named,
      ?fromTags,
      if (placeholder) named,
    ];
    final seen = <String>{};
    return [
      for (final query in ordered)
        if (query.isSearchable && seen.add(query._identity)) query,
    ];
  }

  /// Whether [raw] names a recording rather than a song: only digits and
  /// dates, a recorder's default name ("新录音 3", "Recording 12",
  /// "Track 05", "未命名"), a camera or chat-app file name ("IMG_0034",
  /// "VID_20240501", "PTT-20240501-WA0003") or a hash.
  static bool isPlaceholderName(String raw) {
    final cleaned = cleanTitle(raw).replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return true;
    final lower = cleaned.toLowerCase();
    return _placeholderPatterns.any((pattern) => pattern.hasMatch(lower));
  }

  static final List<RegExp> _placeholderPatterns = [
    RegExp(r'^(?=.*\d)[\d\s\-.:/年月日时分秒]+$'),
    RegExp(
      r'^(新?录音|新?錄音|录音文件|錄音檔|语音|語音|recording|new recording|'
      r'voice memo|voice|audio|track|音轨|音軌|untitled|未命名|未知|unknown|'
      r'record|rec|sound|song|歌曲|新建|default|sample|test)'
      r'[\s\d\-.:()（）#]*$',
    ),
    RegExp(r'^(img|vid|aud|mov|dsc|rec|wa|ptt|audio|voice)[\s\-]*\d{3,}'),
    RegExp(r'^[0-9a-f]{12,}$'),
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'),
  ];

  String get _identity =>
      '${title.toLowerCase().replaceAll(_spaces, '')}|'
      '${artist.toLowerCase().replaceAll(_spaces, '')}';

  /// Whether there is anything to search for.
  bool get isSearchable => title.trim().isNotEmpty;

  /// "歌名 歌手", for sources that search one keyword string.
  String get keywords => artist.isEmpty ? title : '$title $artist';

  OnlineLyricQuery copyWith({String? title, String? artist}) =>
      OnlineLyricQuery(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        duration: duration,
      );

  static final RegExp _extension = RegExp(
    r'\.(mp3|flac|wav|m4a|aac|ogg|opus|ape|wma|aiff?|alac|dsf|mp4|mkv|webm)$',
    caseSensitive: false,
  );
  static final RegExp _trackNumber = RegExp(r'^\s*\d{1,3}\s*[.、_\-]\s*');
  static final RegExp _brackets = RegExp(
    r'\s*[\(\[（【「『<《][^\)\]）】」』>》]*[\)\]）】」』>》]\s*',
  );
  static final RegExp _featuring = RegExp(
    r'\s+(feat\.?|ft\.?|featuring)\s+.*$',
    caseSensitive: false,
  );
  static final RegExp _artistTitle = RegExp(r'^(.+?)\s+[-–—－]\s+(.+)$');
  static final RegExp _spaces = RegExp(r'\s+');

  /// The song title without file extension, track number, bracketed extras
  /// ((Live), [MV], 【伴奏】) or "feat." credits. Brackets are kept when the
  /// title would otherwise be empty.
  static String cleanTitle(String raw) {
    var text = raw.trim().replaceAll('_', ' ');
    text = text.replaceFirst(_extension, '');
    final withoutNumber = text.replaceFirst(_trackNumber, '');
    if (withoutNumber.trim().isNotEmpty) text = withoutNumber;
    final withoutBrackets = text.replaceAll(_brackets, ' ').trim();
    if (withoutBrackets.isNotEmpty) text = withoutBrackets;
    text = text.replaceFirst(_featuring, '');
    return text.replaceAll(_spaces, ' ').trim();
  }

  /// The artist without bracketed extras; several artists stay as written.
  static String cleanArtist(String raw) {
    final withoutBrackets = raw.replaceAll(_brackets, ' ').trim();
    final text = withoutBrackets.isEmpty ? raw.trim() : withoutBrackets;
    return text.replaceAll(_spaces, ' ').trim();
  }

  static bool _sameText(String a, String b) =>
      a.toLowerCase().replaceAll(_spaces, '') ==
      b.toLowerCase().replaceAll(_spaces, '');
}
