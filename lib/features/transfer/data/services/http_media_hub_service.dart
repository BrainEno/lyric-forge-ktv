import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';

class HttpMediaHubService implements MediaHubService {
  static const int preferredPort = 48517;

  final Uuid _uuid;
  final StreamController<MediaHubState> _stateController =
      StreamController<MediaHubState>.broadcast();

  HttpServer? _server;
  Map<String, SharedAudioTrack> _tracks = const {};
  MediaHubState _state = const MediaHubState.stopped();

  HttpMediaHubService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Stream<MediaHubState> get stateStream => _stateController.stream;

  @override
  MediaHubState get currentState => _state;

  @override
  MediaHubSession? get currentSession => _state.session;

  @override
  bool get isRunning => _server != null && _state.isRunning;

  @override
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks) async {
    if (tracks.isEmpty) {
      throw const MediaHubException('至少需要选择一个音频文件才能开始共享');
    }

    await stopSharing();
    _emit(const MediaHubState(status: MediaHubStatus.starting));

    try {
      final validated = <String, SharedAudioTrack>{};
      for (final track in tracks) {
        if (validated.containsKey(track.id)) {
          throw MediaHubException('存在重复的曲目 ID: ' + track.id);
        }

        final file = File(track.localPath);
        if (!await file.exists()) {
          throw MediaHubException('音频文件不存在: ' + track.title);
        }

        final actualLength = await file.length();
        validated[track.id] = SharedAudioTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          localPath: track.localPath,
          format: track.format,
          byteLength: actualLength,
          duration: track.duration,
        );
      }

      final server = await _bindServer();
      final endpoints = await _resolveReachableEndpoints(server.port);
      final preferredEndpoint = endpoints.first;
      final session = MediaHubSession(
        host: preferredEndpoint.host,
        port: server.port,
        token: _uuid.v4().replaceAll('-', ''),
        startedAt: DateTime.now(),
        trackCount: validated.length,
        endpoints: endpoints,
      );

      _tracks = Map.unmodifiable(validated);
      _server = server;
      _emit(
        MediaHubState(
          status: MediaHubStatus.running,
          session: session,
        ),
      );

      server.listen((request) {
        unawaited(_handleRequest(request, session));
      });

      return session;
    } catch (error) {
      await _server?.close(force: true);
      _server = null;
      _tracks = const {};
      _emit(
        MediaHubState(
          status: MediaHubStatus.failed,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> stopSharing() async {
    final server = _server;
    _server = null;
    _tracks = const {};
    if (server != null) {
      await server.close(force: true);
    }
    _emit(const MediaHubState.stopped());
  }

  Future<void> dispose() async {
    await stopSharing();
    await _stateController.close();
  }

  Future<HttpServer> _bindServer() async {
    try {
      return await HttpServer.bind(
        InternetAddress.anyIPv4,
        preferredPort,
      );
    } on SocketException {
      return HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
  }

  Future<List<MediaHubEndpoint>> _resolveReachableEndpoints(int port) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final tailscaleHosts = <String>{};
    final lanHosts = <String>{};
    final otherHosts = <String>{};

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (_isTailscaleIpv4(value)) {
          tailscaleHosts.add(value);
        } else if (_isPrivateLanIpv4(value)) {
          lanHosts.add(value);
        } else {
          otherHosts.add(value);
        }
      }
    }

    final endpoints = <MediaHubEndpoint>[
      ...tailscaleHosts.map(
        (host) => MediaHubEndpoint(
          host: host,
          port: port,
          kind: MediaHubEndpointKind.tailscale,
        ),
      ),
      ...lanHosts.map(
        (host) => MediaHubEndpoint(
          host: host,
          port: port,
          kind: MediaHubEndpointKind.lan,
        ),
      ),
      ...otherHosts.map(
        (host) => MediaHubEndpoint(
          host: host,
          port: port,
          kind: MediaHubEndpointKind.other,
        ),
      ),
    ];

    if (endpoints.isEmpty) {
      endpoints.add(
        MediaHubEndpoint(
          host: InternetAddress.loopbackIPv4.address,
          port: port,
          kind: MediaHubEndpointKind.other,
        ),
      );
    }

    return List.unmodifiable(endpoints);
  }

  Future<void> _handleRequest(
    HttpRequest request,
    MediaHubSession session,
  ) async {
    _applyCommonHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (!_isAuthorized(request, session.token)) {
        await _writeJson(
          request.response,
          HttpStatus.unauthorized,
          {'error': 'unauthorized'},
        );
        return;
      }

      final segments = request.uri.pathSegments;

      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'health') {
        await _writeJson(
          request.response,
          HttpStatus.ok,
          {
            'status': 'ok',
            'protocolVersion': 1,
            'startedAt': session.startedAt.toIso8601String(),
            'trackCount': _tracks.length,
            'remoteAccessAvailable': session.remoteAccessAvailable,
            'endpoints':
                session.endpoints.map((endpoint) => endpoint.toJson()).toList(),
          },
        );
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'tracks') {
        await _writeJson(
          request.response,
          HttpStatus.ok,
          {
            'tracks': _tracks.values.map(_trackPublicJson).toList(),
          },
        );
        return;
      }

      final isAudioRequest =
          (request.method == 'GET' || request.method == 'HEAD') &&
              segments.length == 4 &&
              segments[0] == 'v1' &&
              segments[1] == 'tracks' &&
              segments[3] == 'audio';

      if (isAudioRequest) {
        final track = _tracks[segments[2]];
        if (track == null) {
          await _writeJson(
            request.response,
            HttpStatus.notFound,
            {'error': 'track_not_found'},
          );
          return;
        }

        await _serveAudio(request, track);
        return;
      }

      await _writeJson(
        request.response,
        HttpStatus.notFound,
        {'error': 'not_found'},
      );
    } catch (error) {
      try {
        await _writeJson(
          request.response,
          HttpStatus.internalServerError,
          {'error': 'internal_error', 'message': error.toString()},
        );
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _serveAudio(
    HttpRequest request,
    SharedAudioTrack track,
  ) async {
    final file = File(track.localPath);
    if (!await file.exists()) {
      await _writeJson(
        request.response,
        HttpStatus.gone,
        {'error': 'source_file_missing'},
      );
      return;
    }

    final length = await file.length();
    final parsed = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );

    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType =
        ContentType.parse(_mimeTypeFor(track.format));
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, no-store',
    );

    if (!parsed.isValid) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */' + length.toString(),
      );
      await request.response.close();
      return;
    }

    final range = parsed.range;
    if (range == null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = length;

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.partialContent;
    request.response.contentLength = range.length;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ' +
          range.start.toString() +
          '-' +
          range.endInclusive.toString() +
          '/' +
          length.toString(),
    );

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    await request.response.addStream(
      file.openRead(range.start, range.endInclusive + 1),
    );
    await request.response.close();
  }

  Map<String, dynamic> _trackPublicJson(SharedAudioTrack track) {
    final encodedId = Uri.encodeComponent(track.id);
    return {
      ...track.toPublicJson(),
      'streamPath': '/v1/tracks/' + encodedId + '/audio',
      'downloadPath': '/v1/tracks/' + encodedId + '/audio?download=1',
    };
  }

  bool _isAuthorized(HttpRequest request, String token) {
    final queryToken = request.uri.queryParameters['token'];
    if (queryToken == token) return true;

    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization == null) return false;

    const prefix = 'Bearer ';
    return authorization.startsWith(prefix) &&
        authorization.substring(prefix.length) == token;
  }

  bool _isTailscaleIpv4(String address) {
    final parts = _parseIpv4(address);
    if (parts == null) return false;

    final first = parts[0];
    final second = parts[1];
    return first == 100 && second >= 64 && second <= 127;
  }

  bool _isPrivateLanIpv4(String address) {
    final parts = _parseIpv4(address);
    if (parts == null) return false;

    final first = parts[0];
    final second = parts[1];

    if (first == 10) return true;
    if (first == 192 && second == 168) return true;
    return first == 172 && second >= 16 && second <= 31;
  }

  List<int>? _parseIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return null;

    final parsed = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      parsed.add(value);
    }
    return parsed;
  }

  String _mimeTypeFor(String format) {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      default:
        return 'application/octet-stream';
    }
  }

  _ParsedRange _parseRange(String? header, int length) {
    if (header == null || header.isEmpty) {
      return const _ParsedRange.none();
    }

    if (!header.startsWith('bytes=') || header.contains(',')) {
      return const _ParsedRange.invalid();
    }

    final value = header.substring('bytes='.length);
    final separator = value.indexOf('-');
    if (separator < 0) {
      return const _ParsedRange.invalid();
    }

    final startText = value.substring(0, separator).trim();
    final endText = value.substring(separator + 1).trim();

    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0 || length <= 0) {
        return const _ParsedRange.invalid();
      }

      final clamped = suffixLength > length ? length : suffixLength;
      return _ParsedRange.valid(
        _ByteRange(length - clamped, length - 1),
      );
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= length) {
      return const _ParsedRange.invalid();
    }

    var endInclusive = length - 1;
    if (endText.isNotEmpty) {
      final requestedEnd = int.tryParse(endText);
      if (requestedEnd == null || requestedEnd < start) {
        return const _ParsedRange.invalid();
      }
      endInclusive = requestedEnd >= length ? length - 1 : requestedEnd;
    }

    return _ParsedRange.valid(_ByteRange(start, endInclusive));
  }

  void _applyCommonHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Authorization, Range, Content-Type',
    );
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, HEAD, OPTIONS',
    );
    response.headers.set('X-LyricForge-Protocol', '1');
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  void _emit(MediaHubState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}

class MediaHubException implements Exception {
  final String message;

  const MediaHubException(this.message);

  @override
  String toString() => 'MediaHubException: ' + message;
}

class _ByteRange {
  final int start;
  final int endInclusive;

  const _ByteRange(this.start, this.endInclusive);

  int get length => endInclusive - start + 1;
}

class _ParsedRange {
  final bool isValid;
  final _ByteRange? range;

  const _ParsedRange.none()
      : isValid = true,
        range = null;

  const _ParsedRange.invalid()
      : isValid = false,
        range = null;

  const _ParsedRange.valid(this.range) : isValid = true;
}
