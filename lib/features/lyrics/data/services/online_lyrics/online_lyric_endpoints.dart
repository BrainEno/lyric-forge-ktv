import '../../../domain/online/online_lyric_query.dart';

/// Every remote address the online lyric search uses, in one place.
///
/// Only the song title, artist and duration are sent. LRCLIB is an open
/// lyric database with a documented API; the NetEase and Kugou addresses are
/// the public endpoints their own clients use, so a change on their side can
/// make one source fail — the search then continues with the others.
class OnlineLyricEndpoints {
  const OnlineLyricEndpoints._();

  static const String userAgent =
      'LyricForgeKTV (https://github.com/BrainEno/lyric-forge-ktv)';

  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  static const String neteaseReferer = 'https://music.163.com/';

  /// LRCLIB search by fields when the artist is known, otherwise free text.
  static Uri lrclibSearch(OnlineLyricQuery query, {bool freeText = false}) {
    final parameters = freeText || query.artist.isEmpty
        ? {'q': query.keywords}
        : {'track_name': query.title, 'artist_name': query.artist};
    return Uri.https('lrclib.net', '/api/search', parameters);
  }

  static Uri neteaseSearch(String keywords, {int limit = 6}) => Uri.https(
    'music.163.com',
    '/api/cloudsearch/pc',
    {'s': keywords, 'type': '1', 'limit': '$limit', 'offset': '0'},
  );

  static Uri neteaseLyric(String songId) =>
      Uri.https('music.163.com', '/api/song/lyric', {'id': songId, 'lv': '1'});

  static Uri kugouSearch(String keyword, Duration? duration) =>
      Uri.https('krcs.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'mobi',
        'keyword': keyword,
        'duration': duration == null ? '' : '${duration.inMilliseconds}',
        'hash': '',
      });

  static Uri kugouDownload(String id, String accessKey) =>
      Uri.https('lyrics.kugou.com', '/download', {
        'ver': '1',
        'client': 'pc',
        'id': id,
        'accesskey': accessKey,
        'fmt': 'lrc',
        'charset': 'utf8',
      });
}
