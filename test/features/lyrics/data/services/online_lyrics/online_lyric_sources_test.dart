import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/online_lyrics/online_lyric_http.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/online_lyrics/online_lyric_sources.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';

/// Answers requests by host and path; records every request.
class _FakeHttp {
  _FakeHttp(this.routes);

  final Map<String, String Function(Uri uri)> routes;
  final List<Uri> requests = [];
  final List<Map<String, String>> headers = [];

  Future<String> get(Uri uri, {Map<String, String> headers = const {}}) async {
    requests.add(uri);
    this.headers.add(headers);
    final route = routes['${uri.host}${uri.path}'];
    if (route == null) throw OnlineLyricHttpException(404, uri);
    return route(uri);
  }
}

const _query = OnlineLyricQuery(
  title: '夜航',
  artist: '林小雨',
  duration: Duration(seconds: 200),
);

void main() {
  group('LrclibLyricSource', () {
    test('优先使用带时间戳的歌词，跳过纯音乐', () async {
      final http = _FakeHttp({
        'lrclib.net/api/search': (_) => jsonEncode([
          {
            'id': 7,
            'trackName': '夜航',
            'artistName': '林小雨',
            'duration': 200.5,
            'instrumental': false,
            'plainLyrics': '窗外的雨停了又下',
            'syncedLyrics': '[00:10.00]窗外的雨停了又下',
          },
          {
            'id': 8,
            'trackName': '夜航 (伴奏)',
            'artistName': '林小雨',
            'instrumental': true,
            'plainLyrics': null,
            'syncedLyrics': null,
          },
        ]),
      });
      final found = await LrclibLyricSource(get: http.get).search(_query);
      expect(found, hasLength(1));
      expect(found.single.source, OnlineLyricSourceKind.lrclib);
      expect(found.single.sourceId, '7');
      expect(found.single.lyricText, '[00:10.00]窗外的雨停了又下');
      expect(found.single.duration, const Duration(milliseconds: 200500));
      expect(http.requests.single.queryParameters['track_name'], '夜航');
      expect(http.requests.single.queryParameters['artist_name'], '林小雨');
    });

    test('按字段找不到时改用关键字再找一次', () async {
      final http = _FakeHttp({
        'lrclib.net/api/search': (uri) => uri.queryParameters.containsKey('q')
            ? jsonEncode([
                {'id': 1, 'trackName': '夜航', 'plainLyrics': '窗外的雨停了又下'},
              ])
            : '[]',
      });
      final found = await LrclibLyricSource(get: http.get).search(_query);
      expect(found, hasLength(1));
      expect(http.requests, hasLength(2));
      expect(http.requests.last.queryParameters['q'], '夜航 林小雨');
    });
  });

  group('NeteaseLyricSource', () {
    test('翻唱指向原曲，按原曲编号取歌词', () async {
      final http = _FakeHttp({
        'music.163.com/api/cloudsearch/pc': (_) => jsonEncode({
          'result': {
            'songs': [
              {
                'id': 900,
                'name': '夜航 (翻唱)',
                'ar': [
                  {'name': '某翻唱'},
                ],
                'dt': 199000,
                'originSongSimpleData': {
                  'songId': 100,
                  'name': '夜航',
                  'artists': [
                    {'name': '林小雨'},
                  ],
                },
              },
              {
                'id': 100,
                'name': '夜航',
                'ar': [
                  {'name': '林小雨'},
                ],
                'dt': 200000,
              },
            ],
          },
        }),
        'music.163.com/api/song/lyric': (uri) => jsonEncode({
          'lrc': {'lyric': '[00:10.00]窗外的雨停了又下 ${uri.queryParameters['id']}'},
        }),
      });
      final found = await NeteaseLyricSource(get: http.get).search(_query);
      expect(found, hasLength(1));
      expect(found.single.sourceId, '100');
      expect(found.single.title, '夜航');
      expect(found.single.artist, '林小雨');
      expect(found.single.lyricText, endsWith('100'));
      expect(http.headers.first['Referer'], isNotNull);
    });

    test('没有歌词的歌曲被跳过，单首取词失败不影响其他', () async {
      final http = _FakeHttp({
        'music.163.com/api/cloudsearch/pc': (_) => jsonEncode({
          'result': {
            'songs': [
              {'id': 1, 'name': 'A', 'ar': []},
              {'id': 2, 'name': 'B', 'ar': []},
              {'id': 3, 'name': 'C', 'ar': []},
            ],
          },
        }),
        'music.163.com/api/song/lyric': (uri) {
          final id = uri.queryParameters['id'];
          if (id == '1') return jsonEncode({'nolyric': true});
          if (id == '2') throw const SocketException('reset');
          return jsonEncode({
            'lrc': {'lyric': '[00:01.00]歌词'},
          });
        },
      });
      final found = await NeteaseLyricSource(get: http.get).search(_query);
      expect(found.map((c) => c.sourceId), ['3']);
    });

    test('搜索接口不可用时抛出，由搜索服务记录失败', () async {
      final http = _FakeHttp({});
      await expectLater(
        NeteaseLyricSource(get: http.get).search(_query),
        throwsA(isA<OnlineLyricHttpException>()),
      );
    });
  });

  group('KugouLyricSource', () {
    test('按「歌手 - 歌名」和时长搜索，解码 Base64 歌词', () async {
      const lrc = '[ti:夜航]\r\n[00:10.00]窗外的雨停了又下\r\n';
      final http = _FakeHttp({
        'krcs.kugou.com/search': (_) => jsonEncode({
          'candidates': [
            {
              'id': '55',
              'accesskey': 'KEY',
              'song': '夜航',
              'singer': '林小雨',
              'duration': 200100,
            },
            {'id': '', 'accesskey': 'x'},
          ],
        }),
        'lyrics.kugou.com/download': (uri) {
          expect(uri.queryParameters['id'], '55');
          expect(uri.queryParameters['accesskey'], 'KEY');
          return jsonEncode({'content': base64.encode(utf8.encode(lrc))});
        },
      });
      final found = await KugouLyricSource(get: http.get).search(_query);
      expect(found, hasLength(1));
      expect(found.single.lyricText, lrc);
      expect(found.single.duration, const Duration(milliseconds: 200100));
      final search = http.requests.first;
      expect(search.queryParameters['keyword'], '林小雨 - 夜航');
      expect(search.queryParameters['duration'], '200000');
    });

    test('损坏的 Base64 内容视为没有歌词', () {
      expect(KugouLyricSource.parseDownload('{"content":"%%%"}'), isEmpty);
    });
  });
}
