import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

class HttpMediaHubClientService implements MediaHubClientService {
  final HttpClient _httpClient;
  MediaHubConnection? _connection;

  HttpMediaHubClientService({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  @override
  MediaHubConnection? get currentConnection => _connection;

  @override
  bool get isConnected => _connection != null;

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) async {
    final connection = MediaHubConnection.fromPairingUri(pairingUri);
    await connectTo(connection);
    return connection;
  }

  @override
  Future<void> connectTo(MediaHubConnection connection) async {
    final response = await _authorizedGet(
      connection,
      connection.resolve('/v1/health'),
    );

    try {
      if (response.statusCode != HttpStatus.ok) {
        throw MediaHubClientException(
          '连接桌面端失败，HTTP ${response.statusCode}',
        );
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != 'ok') {
        throw const MediaHubClientException('桌面端返回了无效的健康检查响应');
      }
      if (decoded['protocolVersion'] != 1) {
        throw const MediaHubClientException('桌面端 Media Hub 协议版本不兼容');
      }

      _connection = connection;
    } on FormatException catch (error) {
      throw MediaHubClientException('无法解析桌面端响应: $error');
    }
  }

  @override
  Future<void> disconnect() async {
    _connection = null;
  }

  @override
  Future<List<RemoteAudioTrack>> fetchTracks() async {
    final connection = _requireConnection();
    final response = await _authorizedGet(
      connection,
      connection.resolve('/v1/tracks'),
    );

    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw MediaHubClientException(
        '获取桌面曲目失败，HTTP ${response.statusCode}',
      );
    }

    try {
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('响应不是 JSON 对象');
      }

      final tracks = decoded['tracks'];
      if (tracks is! List) {
        throw const FormatException('响应缺少 tracks');
      }

      return tracks
          .map((item) {
            if (item is! Map) {
              throw const FormatException('曲目数据格式无效');
            }
            return RemoteAudioTrack.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw MediaHubClientException('无法解析桌面曲目列表: $error');
    }
  }

  @override
  Uri playbackUriFor(RemoteAudioTrack track) {
    final connection = _requireConnection();
    final uri = connection.resolve(track.streamPath);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'token': connection.token,
      },
    );
  }

  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) async {
    if (!track.hasLyrics || track.lyricsPath == null) return null;

    final connection = _requireConnection();
    final response = await _authorizedGet(
      connection,
      connection.resolve(track.lyricsPath!),
    );

    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw MediaHubClientException(
        '获取远程歌词失败，HTTP ${response.statusCode}',
      );
    }

    try {
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('歌词响应不是 JSON 对象');
      }
      final lyrics = decoded['lyrics'];
      if (lyrics is! Map) {
        throw const FormatException('歌词响应缺少 lyrics');
      }
      return LyricDocument.fromJson(Map<String, dynamic>.from(lyrics));
    } on FormatException catch (error) {
      throw MediaHubClientException('无法解析远程歌词: $error');
    }
  }

  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) async {
    final connection = _requireConnection();
    final uri = connection.resolve(track.downloadPath);
    final response = await _authorizedGet(connection, uri);

    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw MediaHubClientException(
        '下载音频失败，HTTP ${response.statusCode}',
      );
    }

    final destination = File(destinationPath);
    final partial = File('$destinationPath.part');
    await partial.parent.create(recursive: true);

    if (await partial.exists()) {
      await partial.delete();
    }

    final sink = partial.openWrite();
    var transferred = 0;
    final total = response.contentLength > 0 ? response.contentLength : null;

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        transferred += chunk.length;
        onProgress?.call(transferred, total);
      }
      await sink.flush();
      await sink.close();

      if (await destination.exists()) {
        await destination.delete();
      }
      await partial.rename(destination.path);
    } catch (error) {
      await sink.close();
      if (await partial.exists()) {
        await partial.delete();
      }
      throw MediaHubClientException('下载音频失败: $error');
    }
  }

  @override
  Future<void> dispose() async {
    _connection = null;
    _httpClient.close(force: true);
  }

  Future<HttpClientResponse> _authorizedGet(
    MediaHubConnection connection,
    Uri uri,
  ) async {
    try {
      final request = await _httpClient.getUrl(uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${connection.token}',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      return await request.close();
    } on SocketException catch (error) {
      throw MediaHubClientException('无法连接桌面端: ${error.message}');
    } on HttpException catch (error) {
      throw MediaHubClientException('桌面端连接失败: ${error.message}');
    }
  }

  MediaHubConnection _requireConnection() {
    final connection = _connection;
    if (connection == null) {
      throw const MediaHubClientException('尚未连接桌面 Media Hub');
    }
    return connection;
  }
}

class MediaHubClientException implements Exception {
  final String message;

  const MediaHubClientException(this.message);

  @override
  String toString() => 'MediaHubClientException: $message';
}
