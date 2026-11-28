import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';
import 'http_media_hub_disk_space_probe.dart';
import 'http_media_hub_incoming_upload_handler.dart';
import 'http_media_hub_media_responder.dart';
import 'media_hub_discovery_auth.dart';
import 'media_hub_tls_identity_store.dart';

export 'http_media_hub_disk_space_probe.dart'
    show mediaHubWindowsDiskSpaceProbeScript;
export 'http_media_hub_incoming_upload_handler.dart'
    show IncomingDiskSpaceProbe, IncomingMediaCallback;

class HttpMediaHubService implements MediaHubService {
  static const String _logTag = 'transfer.hub';

  static const int preferredPort = 48517;
  static const int defaultMaxIncomingAudioBytes = 2 * 1024 * 1024 * 1024;
  static const Duration defaultIncomingUploadIdleTimeout = Duration(
    seconds: 30,
  );
  static const Duration defaultIncomingUploadTotalTimeout = Duration(
    minutes: 45,
  );
  static const int defaultMinimumFreeSpaceBytes = 256 * 1024 * 1024;

  /// How long a rejected upload's remaining body is read and discarded after
  /// the error response was sent. Closing a TLS connection while request bytes
  /// are still unread makes the kernel reset it, and a reset can destroy a
  /// response the client had not yet read; draining briefly lets the client
  /// see why its upload was refused (#441).
  static const Duration defaultIncomingRejectionDrainGrace = Duration(
    seconds: 1,
  );

  final Uuid _uuid;
  final MediaHubTlsIdentityStore _tlsIdentityStore;
  final Directory? incomingDirectory;
  final IncomingMediaCallback? onIncomingFile;
  final int maxIncomingAudioBytes;
  final Duration incomingUploadIdleTimeout;
  final Duration incomingUploadTotalTimeout;
  final Duration incomingRejectionDrainGrace;
  final int minimumFreeSpaceBytes;
  final IncomingDiskSpaceProbe _diskSpaceProbe;
  late final HttpMediaHubIncomingUploadHandler _incomingUploadHandler =
      HttpMediaHubIncomingUploadHandler(
        logTag: _logTag,
        uuid: _uuid,
        incomingDirectory: incomingDirectory,
        onIncomingFile: onIncomingFile,
        maxIncomingAudioBytes: maxIncomingAudioBytes,
        incomingUploadIdleTimeout: incomingUploadIdleTimeout,
        incomingUploadTotalTimeout: incomingUploadTotalTimeout,
        incomingRejectionDrainGrace: incomingRejectionDrainGrace,
        minimumFreeSpaceBytes: minimumFreeSpaceBytes,
        diskSpaceProbe: _diskSpaceProbe,
        writeJson: _writeJson,
      );
  late final HttpMediaHubMediaResponder _mediaResponder =
      HttpMediaHubMediaResponder(writeJson: _writeJson);
  final StreamController<MediaHubState> _stateController =
      StreamController<MediaHubState>.broadcast();

  final List<HttpServer> _servers = <HttpServer>[];
  Map<String, SharedAudioTrack> _tracks = const {};
  MediaHubState _state = const MediaHubState.stopped();

  HttpMediaHubService({
    Uuid? uuid,
    MediaHubTlsIdentityStore? tlsIdentityStore,
    this.incomingDirectory,
    this.onIncomingFile,
    this.maxIncomingAudioBytes = defaultMaxIncomingAudioBytes,
    this.incomingUploadIdleTimeout = defaultIncomingUploadIdleTimeout,
    this.incomingUploadTotalTimeout = defaultIncomingUploadTotalTimeout,
    this.incomingRejectionDrainGrace = defaultIncomingRejectionDrainGrace,
    this.minimumFreeSpaceBytes = defaultMinimumFreeSpaceBytes,
    IncomingDiskSpaceProbe? diskSpaceProbe,
  }) : _uuid = uuid ?? const Uuid(),
       _tlsIdentityStore = tlsIdentityStore ?? MediaHubTlsIdentityStore(),
       _diskSpaceProbe = diskSpaceProbe ?? probeAvailableDiskSpaceBytes {
    if (maxIncomingAudioBytes <= 0) {
      throw ArgumentError.value(
        maxIncomingAudioBytes,
        'maxIncomingAudioBytes',
        'Must be greater than zero.',
      );
    }
    if (incomingUploadIdleTimeout <= Duration.zero ||
        incomingUploadTotalTimeout <= Duration.zero) {
      throw ArgumentError('Upload timeouts must be greater than zero.');
    }
    if (incomingRejectionDrainGrace < Duration.zero) {
      throw ArgumentError.value(
        incomingRejectionDrainGrace,
        'incomingRejectionDrainGrace',
        'Must not be negative.',
      );
    }
    if (minimumFreeSpaceBytes < 0) {
      throw ArgumentError.value(
        minimumFreeSpaceBytes,
        'minimumFreeSpaceBytes',
        'Must not be negative.',
      );
    }
  }

  @override
  Stream<MediaHubState> get stateStream => _stateController.stream;

  @override
  MediaHubState get currentState => _state;

  @override
  MediaHubSession? get currentSession => _state.session;

  @override
  bool get isRunning => _servers.isNotEmpty && _state.isRunning;

  @override
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks) async {
    await stopSharing();
    _emit(const MediaHubState(status: MediaHubStatus.starting));

    try {
      final validated = <String, SharedAudioTrack>{};
      for (final track in tracks) {
        if (validated.containsKey(track.id)) {
          throw MediaHubException('存在重复的曲目 ID: ${track.id}');
        }

        final file = File(track.localPath);
        if (!await file.exists()) {
          throw MediaHubException('音频文件不存在: ${track.title}');
        }

        String? artworkPath;
        final requestedArtwork = track.artworkPath?.trim();
        if (requestedArtwork != null && requestedArtwork.isNotEmpty) {
          final artwork = File(requestedArtwork);
          if (await artwork.exists()) artworkPath = artwork.path;
        }

        final actualLength = await file.length();
        validated[track.id] = SharedAudioTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          localPath: track.localPath,
          artworkPath: artworkPath,
          format: track.format,
          byteLength: actualLength,
          duration: track.duration,
          lyrics: track.lyrics,
        );
      }

      final tlsIdentity = await _tlsIdentityStore.loadOrCreate();
      final bound = await _bindServers(tlsIdentity);
      _servers.addAll(bound.servers);
      final endpoints = bound.endpoints;
      final preferredEndpoint = endpoints.first;
      final session = MediaHubSession(
        host: preferredEndpoint.host,
        port: preferredEndpoint.port,
        token: _uuid.v4().replaceAll('-', ''),
        startedAt: DateTime.now(),
        trackCount: validated.length,
        endpoints: endpoints,
        tlsFingerprint: tlsIdentity.fingerprint,
      );

      _tracks = Map.unmodifiable(validated);
      _emit(MediaHubState(status: MediaHubStatus.running, session: session));

      for (final server in _servers) {
        server.listen((request) {
          unawaited(_handleRequest(request, session));
        });
      }

      return session;
    } catch (error) {
      await Future.wait(_servers.map((server) => server.close(force: true)));
      _servers.clear();
      _tracks = const {};
      _emit(
        MediaHubState(status: MediaHubStatus.failed, error: error.toString()),
      );
      rethrow;
    }
  }

  @override
  Future<void> stopSharing() async {
    final servers = List<HttpServer>.from(_servers);
    _servers.clear();
    _tracks = const {};
    await Future.wait(servers.map((server) => server.close(force: true)));
    _emit(const MediaHubState.stopped());
  }

  Future<void> dispose() async {
    await stopSharing();
    await _stateController.close();
  }

  Future<_BoundMediaHubServers> _bindServers(
    MediaHubTlsIdentity tlsIdentity,
  ) async {
    final servers = <HttpServer>[];
    final endpoints = <MediaHubEndpoint>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      final tailscaleHosts = <String>{};
      final lanHosts = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final value = address.address;
          if (_isTailscaleIpv4(value)) {
            tailscaleHosts.add(value);
          } else if (_isPrivateLanIpv4(value)) {
            lanHosts.add(value);
          }
          // Do not bind to public or otherwise unclassified interfaces.
        }
      }

      for (final host in tailscaleHosts) {
        await _tryBindEndpoint(
          host,
          MediaHubEndpointKind.tailscale,
          servers,
          endpoints,
          tlsIdentity,
        );
      }
      for (final host in lanHosts) {
        await _tryBindEndpoint(
          host,
          MediaHubEndpointKind.lan,
          servers,
          endpoints,
          tlsIdentity,
        );
      }

      if (endpoints.isEmpty) {
        final loopback = await _bindWithPortFallback(
          InternetAddress.loopbackIPv4.address,
          tlsIdentity,
        );
        servers.add(loopback);
        endpoints.add(
          MediaHubEndpoint(
            host: InternetAddress.loopbackIPv4.address,
            port: loopback.port,
            kind: MediaHubEndpointKind.other,
          ),
        );
      } else {
        // Preserve local-loopback access for desktop callers and tests without
        // exposing the listener on arbitrary network interfaces.
        final primary = endpoints.first;
        try {
          servers.add(
            await HttpServer.bindSecure(
              InternetAddress.loopbackIPv4,
              primary.port,
              tlsIdentity.createServerContext(),
            ),
          );
        } on SocketException {
          // The advertised LAN/Tailscale endpoint remains usable if loopback
          // is unavailable or that local port is occupied.
        }
      }

      return _BoundMediaHubServers(
        servers: List<HttpServer>.unmodifiable(servers),
        endpoints: List<MediaHubEndpoint>.unmodifiable(endpoints),
      );
    } catch (_) {
      await Future.wait(servers.map((server) => server.close(force: true)));
      rethrow;
    }
  }

  Future<void> _tryBindEndpoint(
    String host,
    MediaHubEndpointKind kind,
    List<HttpServer> servers,
    List<MediaHubEndpoint> endpoints,
    MediaHubTlsIdentity tlsIdentity,
  ) async {
    try {
      final server = await _bindWithPortFallback(host, tlsIdentity);
      servers.add(server);
      endpoints.add(
        MediaHubEndpoint(host: host, port: server.port, kind: kind),
      );
    } on SocketException {
      // Skip an unavailable interface; keep successfully bound endpoints.
    }
  }

  Future<HttpServer> _bindWithPortFallback(
    String host,
    MediaHubTlsIdentity tlsIdentity,
  ) async {
    Future<HttpServer> bind(int port) => HttpServer.bindSecure(
      InternetAddress(host),
      port,
      tlsIdentity.createServerContext(),
    );

    try {
      return await bind(preferredPort);
    } on SocketException {
      return bind(0);
    }
  }

  Future<void> _handleRequest(
    HttpRequest request,
    MediaHubSession session,
  ) async {
    _applyCommonHeaders(request.response);

    if (request.method == 'OPTIONS') {
      await _writeJson(request.response, HttpStatus.methodNotAllowed, {
        'error': 'browser_preflight_not_supported',
      });
      return;
    }

    try {
      if (!_isAuthorized(request, session.token)) {
        await _writeJson(request.response, HttpStatus.unauthorized, {
          'error': 'unauthorized',
        });
        return;
      }

      final segments = request.uri.pathSegments;

      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'health') {
        await _writeJson(request.response, HttpStatus.ok, {
          'status': 'ok',
          'protocolVersion': 2,
          'startedAt': session.startedAt.toIso8601String(),
          'trackCount': _tracks.length,
          'acceptsUploads': true,
          'remoteAccessAvailable': session.remoteAccessAvailable,
          'endpoints': session.endpoints
              .map((endpoint) => endpoint.toJson())
              .toList(),
        });
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 2 &&
          segments[0] == 'v1' &&
          segments[1] == 'tracks') {
        await _writeJson(request.response, HttpStatus.ok, {
          'tracks': _tracks.values.map(_trackPublicJson).toList(),
        });
        return;
      }

      final isIncomingAudio =
          request.method == 'POST' &&
          segments.length == 3 &&
          segments[0] == 'v1' &&
          segments[1] == 'incoming' &&
          segments[2] == 'audio';
      if (isIncomingAudio) {
        await _incomingUploadHandler.receiveIncomingAudio(request, session);
        return;
      }

      final isLyricsRequest =
          request.method == 'GET' &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'tracks' &&
          segments[3] == 'lyrics';

      if (isLyricsRequest) {
        final track = _tracks[segments[2]];
        if (track == null) {
          await _writeJson(request.response, HttpStatus.notFound, {
            'error': 'track_not_found',
          });
          return;
        }

        final lyrics = track.lyrics;
        if (lyrics == null || lyrics.lines.isEmpty) {
          await _writeJson(request.response, HttpStatus.notFound, {
            'error': 'lyrics_not_found',
          });
          return;
        }

        await _writeJson(request.response, HttpStatus.ok, {
          'lyrics': lyrics.toJson(),
        });
        return;
      }

      final isArtworkRequest =
          (request.method == 'GET' || request.method == 'HEAD') &&
          segments.length == 4 &&
          segments[0] == 'v1' &&
          segments[1] == 'tracks' &&
          segments[3] == 'artwork';

      if (isArtworkRequest) {
        final track = _tracks[segments[2]];
        if (track == null) {
          await _writeJson(request.response, HttpStatus.notFound, {
            'error': 'track_not_found',
          });
          return;
        }
        await _mediaResponder.serveArtwork(request, track);
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
          await _writeJson(request.response, HttpStatus.notFound, {
            'error': 'track_not_found',
          });
          return;
        }

        await _mediaResponder.serveAudio(request, track);
        return;
      }

      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
    } catch (error) {
      try {
        await _writeJson(request.response, HttpStatus.internalServerError, {
          'error': 'internal_error',
          'message': error.toString(),
        });
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Map<String, dynamic> _trackPublicJson(SharedAudioTrack track) {
    final encodedId = Uri.encodeComponent(track.id);
    return {
      ...track.toPublicJson(),
      'streamPath': '/v1/tracks/$encodedId/audio',
      'downloadPath': '/v1/tracks/$encodedId/audio?download=1',
      if (track.hasLyrics) 'lyricsPath': '/v1/tracks/$encodedId/lyrics',
      if (track.hasArtwork) 'artworkPath': '/v1/tracks/$encodedId/artwork',
    };
  }

  bool _isAuthorized(HttpRequest request, String token) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null) return false;

    const prefix = 'Bearer ';
    return authorization.startsWith(prefix) &&
        mediaHubConstantTimeEquals(
          authorization.substring(prefix.length),
          token,
        );
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

  void _applyCommonHeaders(HttpResponse response) {
    // Media Hub is consumed by the native app over pinned HTTPS. It has no
    // browser client, so do not grant cross-origin JavaScript access.
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

class _BoundMediaHubServers {
  final List<HttpServer> servers;
  final List<MediaHubEndpoint> endpoints;

  const _BoundMediaHubServers({required this.servers, required this.endpoints});
}

class MediaHubException implements Exception {
  final String message;

  const MediaHubException(this.message);

  @override
  String toString() => 'MediaHubException: $message';
}
