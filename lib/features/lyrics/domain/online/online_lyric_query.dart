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
