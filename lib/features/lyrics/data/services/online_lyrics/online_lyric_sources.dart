import 'dart:convert';

import '../../../domain/online/online_lyric_candidate.dart';
import '../../../domain/online/online_lyric_query.dart';
import 'online_lyric_endpoints.dart';
import 'online_lyric_http.dart';

/// LRCLIB: an open, crowd-sourced database of synced lyrics.
class LrclibLyricSource implements OnlineLyricSource {
  final OnlineLyricHttpGet get;
  final int maxCandidates;

  const LrclibLyricSource({required this.get, this.maxCandidates = 5});

  @override
  OnlineLyricSourceKind get kind => OnlineLyricSourceKind.lrclib;

  @override
  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query) async {
    var found = _parse(await get(OnlineLyricEndpoints.lrclibSearch(query)));
    if (found.isEmpty && query.artist.isNotEmpty) {
      // The artist on the project may be spelt differently; try free text.
      found = _parse(
        await get(OnlineLyricEndpoints.lrclibSearch(query, freeText: true)),
      );
    }
    return found.take(maxCandidates).toList(growable: false);
  }

  List<OnlineLyricCandidate> _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final candidates = <OnlineLyricCandidate>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      if (item['instrumental'] == true) continue;
      final synced = _string(item['syncedLyrics']);
      final plain = _string(item['plainLyrics']);
      final text = synced.trim().isNotEmpty ? synced : plain;
      if (text.trim().isEmpty) continue;
      final seconds = item['duration'];
      candidates.add(
        OnlineLyricCandidate(
          source: kind,
          sourceId: '${item['id'] ?? candidates.length}',
          title: _string(item['trackName'] ?? item['name']),
          artist: _string(item['artistName']),
          duration: seconds is num
              ? Duration(milliseconds: (seconds * 1000).round())
              : null,
          lyricText: text,
        ),
      );
    }
    return candidates;
  }
}

/// NetEase Cloud Music: the widest coverage of Chinese-language songs.
class NeteaseLyricSource implements OnlineLyricSource {
  final OnlineLyricHttpGet get;
  final int maxCandidates;

  const NeteaseLyricSource({required this.get, this.maxCandidates = 3});

  @override
  OnlineLyricSourceKind get kind => OnlineLyricSourceKind.netease;

  static const Map<String, String> _headers = {
    'Referer': OnlineLyricEndpoints.neteaseReferer,
    'User-Agent': OnlineLyricEndpoints.browserUserAgent,
  };

  @override
  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query) async {
    final body = await get(
      OnlineLyricEndpoints.neteaseSearch(query.keywords),
      headers: _headers,
    );
    final songs = parseSongs(body).take(maxCandidates).toList();
    final lyrics = await Future.wait([
      for (final song in songs)
        get(
          OnlineLyricEndpoints.neteaseLyric(song.id),
          headers: _headers,
        ).then(parseLyric, onError: (Object _) => ''),
    ]);
    return [
      for (var index = 0; index < songs.length; index++)
        if (lyrics[index].trim().isNotEmpty)
          OnlineLyricCandidate(
            source: kind,
            sourceId: songs[index].id,
            title: songs[index].title,
            artist: songs[index].artist,
            duration: songs[index].duration,
            lyricText: lyrics[index],
          ),
    ];
  }

  /// Songs from a `cloudsearch` response. Covers and re-uploads point to
  /// the original recording, whose lyric is usually the maintained one.
  static List<({String id, String title, String artist, Duration? duration})>
  parseSongs(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final result = decoded['result'];
    if (result is! Map) return const [];
    final songs = result['songs'];
    if (songs is! List) return const [];
    final seen = <String>{};
    final parsed =
        <({String id, String title, String artist, Duration? duration})>[];
    for (final song in songs) {
      if (song is! Map) continue;
      final origin = song['originSongSimpleData'];
      final originId = origin is Map ? origin['songId'] : null;
      final id = '${originId ?? song['id'] ?? ''}';
      if (id.isEmpty || !seen.add(id)) continue;
      final artists = origin is Map ? origin['artists'] : song['ar'];
      final milliseconds = song['dt'];
      parsed.add((
        id: id,
        title: _string(origin is Map ? origin['name'] : song['name']),
        artist: _artistNames(artists),
        duration: milliseconds is num
            ? Duration(milliseconds: milliseconds.round())
            : null,
      ));
    }
    return parsed;
  }

  /// The LRC of a `song/lyric` response; empty when the song has none.
  static String parseLyric(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return '';
    if (decoded['nolyric'] == true || decoded['uncollected'] == true) {
      return '';
    }
    final lrc = decoded['lrc'];
    if (lrc is! Map) return '';
    return _string(lrc['lyric']);
  }

  static String _artistNames(Object? artists) {
    if (artists is! List) return '';
    return [
      for (final artist in artists)
        if (artist is Map && _string(artist['name']).isNotEmpty)
          _string(artist['name']),
    ].join('/');
  }
}

/// Kugou Music: a second large Chinese catalogue, matched by duration.
class KugouLyricSource implements OnlineLyricSource {
  final OnlineLyricHttpGet get;
  final int maxCandidates;

  const KugouLyricSource({required this.get, this.maxCandidates = 3});

  @override
  OnlineLyricSourceKind get kind => OnlineLyricSourceKind.kugou;

  static const Map<String, String> _headers = {
    'User-Agent': OnlineLyricEndpoints.browserUserAgent,
  };

  @override
  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query) async {
    final keyword = query.artist.isEmpty
        ? query.title
        : '${query.artist} - ${query.title}';
    final body = await get(
      OnlineLyricEndpoints.kugouSearch(keyword, query.duration),
      headers: _headers,
    );
    final entries = parseCandidates(body).take(maxCandidates).toList();
    final lyrics = await Future.wait([
      for (final entry in entries)
        get(
          OnlineLyricEndpoints.kugouDownload(entry.id, entry.accessKey),
          headers: _headers,
        ).then(parseDownload, onError: (Object _) => ''),
    ]);
    return [
      for (var index = 0; index < entries.length; index++)
        if (lyrics[index].trim().isNotEmpty)
          OnlineLyricCandidate(
            source: kind,
            sourceId: entries[index].id,
            title: entries[index].title,
            artist: entries[index].artist,
            duration: entries[index].duration,
            lyricText: lyrics[index],
          ),
    ];
  }

  static List<
    ({
      String id,
      String accessKey,
      String title,
      String artist,
      Duration? duration,
    })
  >
  parseCandidates(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final candidates = decoded['candidates'];
    if (candidates is! List) return const [];
    final parsed =
        <
          ({
            String id,
            String accessKey,
            String title,
            String artist,
            Duration? duration,
          })
        >[];
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final id = _string(candidate['id']);
      final accessKey = _string(candidate['accesskey']);
      if (id.isEmpty || accessKey.isEmpty) continue;
      final milliseconds = candidate['duration'];
      parsed.add((
        id: id,
        accessKey: accessKey,
        title: _string(candidate['song']),
        artist: _string(candidate['singer']),
        duration: milliseconds is num
            ? Duration(milliseconds: milliseconds.round())
            : null,
      ));
    }
    return parsed;
  }

  /// The LRC inside a `download` response, which is Base64 encoded.
  static String parseDownload(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return '';
    final content = _string(decoded['content']);
    if (content.isEmpty) return '';
    try {
      return const Utf8Decoder(
        allowMalformed: true,
      ).convert(base64.decode(base64.normalize(content)));
    } on FormatException {
      return '';
    }
  }
}

String _string(Object? value) => value == null ? '' : '$value';
