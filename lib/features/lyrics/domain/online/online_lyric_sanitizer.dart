/// Removes what lyric sites add around the sung words.
///
/// NetEase and Kugou put the credits (作词 : 周杰伦, 编曲：…, Producer: …) and a
/// "歌名 - 歌手" header on timed rows at the start, and mark instrumental
/// tracks with a sentence instead of lyrics. Aligning such rows would insert
/// "作曲 : 周杰伦" into the karaoke draft as a missed line, so they are dropped
/// before the lyric is parsed. Timestamps of the remaining rows are kept as
/// they are.
class OnlineLyricSanitizer {
  const OnlineLyricSanitizer();

  /// Credit labels; a row is a credit when it starts with one of them followed
  /// by a colon within a few characters ("作词 : X", "Lyrics by: X").
  static final RegExp _credit = RegExp(
    r'^\s*(?:作词|作詞|作曲|编曲|編曲|词|詞|曲|填词|填詞|原唱|翻唱|演唱|歌手|'
    r'制作人|製作人|制作|製作|监制|監製|出品|出品人|发行|發行|统筹|統籌|策划|策劃|'
    r'和声|和聲|和音|伴唱|和声编写|和聲編寫|配唱|配唱制作人|人声|人聲|'
    r'吉他|电吉他|電吉他|木吉他|贝斯|貝斯|鼓|架子鼓|键盘|鍵盤|钢琴|鋼琴|弦乐|弦樂|'
    r'小提琴|大提琴|二胡|笛子|琵琶|古筝|古箏|合成器|采样|採樣|打击乐|打擊樂|'
    r'录音|錄音|录音师|錄音師|录音室|錄音室|录音工程|錄音工程|录音助理|錄音助理|'
    r'混音|混音师|混音師|混音工程|母带|母帶|母带工程|母帶工程|缩混|縮混|'
    r'音乐总监|音樂總監|音乐制作|音樂製作|视觉|視覺|封面|设计|設計|文案|'
    r'版权|版權|企划|企劃|宣传|宣傳|营销|營銷|OP|SP|ISRC|'
    r'lyrics?|lyricist|written|writer|composer|composed|music|arranger|arranged|'
    r'arrangement|producer|produced|production|executive|mix(?:ed|ing)?|'
    r'master(?:ed|ing)?|record(?:ed|ing)?|engineer|vocals?|backing|guitars?|'
    r'bass|drums?|keyboards?|piano|strings?|programming|publisher|label)'
    r'[^:：\n]{0,16}[:：]',
    caseSensitive: false,
  );

  /// Phrases sites use instead of lyrics for instrumental tracks.
  static final RegExp _instrumental = RegExp(
    r'纯音乐|純音樂|此歌曲为没有填词|此歌曲為沒有填詞|暂无歌词|暫無歌詞|'
    r'没有歌词|沒有歌詞|instrumental',
    caseSensitive: false,
  );

  static final RegExp _leadingTags = RegExp(r'^(\s*\[[^\]]*\])*');
  static final RegExp _timestamp = RegExp(
    r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
  );
  static final RegExp _header = RegExp(r'^.{1,60}\s[-–—]\s.{1,60}$');

  /// [raw] without credits, title header rows and site notices. Returns an
  /// empty string when nothing sung is left (an instrumental track).
  String sanitize(String raw, {String title = '', String artist = ''}) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final kept = <String>[];
    var sungRows = 0;
    var checkedHeaderRows = 0;
    for (final line in lines) {
      final tags = _leadingTags.firstMatch(line)?.group(0) ?? '';
      final text = line.substring(tags.length).trim();
      if (text.isEmpty) {
        // Keep timed end markers and LRC metadata; drop blank plain rows.
        if (tags.isNotEmpty) kept.add(line);
        continue;
      }
      if (_credit.hasMatch(text)) continue;
      if (sungRows == 0 && checkedHeaderRows < 3) {
        checkedHeaderRows++;
        if (_isHeader(text, title: title, artist: artist)) continue;
      }
      if (_isNotice(text)) continue;
      kept.add(line);
      sungRows++;
    }
    if (sungRows == 0) return '';
    return kept.join('\n');
  }

  /// Whether [raw] is a timed lyric (LRC) rather than plain text.
  bool isTimed(String raw) => _timestamp.hasMatch(raw);

  bool _isHeader(String text, {required String title, required String artist}) {
    final normalized = _normalize(text);
    final normalizedTitle = _normalize(title);
    // Only "歌名 - 歌手" rows: a first row that is just the title can be sung.
    if (normalizedTitle.isEmpty || !_header.hasMatch(text)) return false;
    final normalizedArtist = _normalize(artist);
    return normalized.contains(normalizedTitle) &&
        (normalizedArtist.isEmpty || normalized.contains(normalizedArtist));
  }

  bool _isNotice(String text) {
    if (!_instrumental.hasMatch(text)) return false;
    // A sung row may contain the word; only short notice rows are dropped.
    return text.runes.length <= 24;
  }

  static String _normalize(String text) => text.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );
}
