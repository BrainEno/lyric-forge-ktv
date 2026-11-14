import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../player/domain/services/audio_library_import_service.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';
import 'media_hub_discovery_auth.dart';
import 'media_hub_tls_identity_store.dart';

typedef IncomingMediaCallback = Future<void> Function(String path);
typedef IncomingDiskSpaceProbe = Future<int?> Function(Directory directory);

class HttpMediaHubService implements MediaHubService {
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
  static const int _maximumRejectedBodyDrainBytes = 16 * 1024 * 1024;
  static const int _incomingUploadDiskSpaceCheckIntervalBytes =
      64 * 1024 * 1024;
  static const int _maximumConcurrentIncomingUploads = 2;
  static int _activeIncomingUploads = 0;
  static final Set<String> _activeIncomingSessionTokens = <String>{};

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
       _diskSpaceProbe = diskSpaceProbe ?? _probeAvailableDiskSpaceBytes {
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
        await _receiveIncomingAudio(request, session);
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
        await _serveArtwork(request, track);
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

        await _serveAudio(request, track);
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

  Future<void> _receiveIncomingAudio(
    HttpRequest request,
    MediaHubSession session,
  ) async {
    final rawName = request.uri.queryParameters['filename']?.trim();
    if (rawName == null || rawName.isEmpty) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.badRequest,
        'missing_filename',
      );
      return;
    }

    final safeName = _safeIncomingName(rawName);
    final dot = safeName.lastIndexOf('.');
    final extension = dot < 0 ? '' : safeName.substring(dot + 1).toLowerCase();
    if (!supportedLocalAudioExtensions.contains(extension)) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.unsupportedMediaType,
        'unsupported_audio_extension',
      );
      return;
    }

    final expectedLength = request.contentLength >= 0
        ? request.contentLength
        : null;
    if (expectedLength != null && expectedLength > maxIncomingAudioBytes) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.requestEntityTooLarge,
        'upload_too_large',
        details: {'maxBytes': maxIncomingAudioBytes},
      );
      return;
    }

    if (!_tryReserveIncomingUpload(session.token)) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.tooManyRequests,
        'upload_limit_reached',
        retryAfterSeconds: 5,
      );
      return;
    }

    File? partialFile;
    _IncomingUploadReservation? incomingReservation;
    IOSink? uploadSink;
    StreamIterator<List<int>>? uploadIterator;
    Future<bool>? pendingMoveNext;
    Timer? idleTimer;
    Timer? totalTimer;
    var resourcesReleased = false;

    void cancelUploadTimers() {
      idleTimer?.cancel();
      idleTimer = null;
      totalTimer?.cancel();
      totalTimer = null;
    }

    // Everything the upload holds on disk and in the session is released
    // before the client is told the outcome, so a client (or test) that reacts
    // to the response never observes a stale partial file, reservation marker,
    // or busy upload slot.
    Future<void> releaseUploadResources() async {
      if (resourcesReleased) return;
      resourcesReleased = true;
      cancelUploadTimers();
      await _discardPartialUpload(uploadSink, partialFile);
      uploadSink = null;
      partialFile = null;
      final reservation = incomingReservation;
      incomingReservation = null;
      if (reservation != null) {
        await _releaseIncomingDestinationReservation(reservation);
      }
      _releaseIncomingUpload(session.token);
    }

    Future<void> rejectInFlight(
      int statusCode,
      String errorCode, {
      Map<String, dynamic> details = const {},
    }) async {
      await releaseUploadResources();
      await _rejectIncomingUpload(
        request,
        statusCode,
        errorCode,
        details: details,
        body: uploadIterator,
        pendingMoveNext: pendingMoveNext,
      );
    }

    try {
      final directory = await _resolveIncomingDirectory();
      await directory.create(recursive: true);

      final availableBytes = await _availableDiskSpace(directory);
      if (availableBytes == null) {
        throw const _IncomingUploadStorageCheckUnavailable();
      }
      if (!_hasEnoughFreeSpace(availableBytes, expectedLength ?? 0)) {
        throw const _IncomingUploadInsufficientSpace();
      }

      final reservation = await _reserveIncomingDestination(
        directory,
        safeName,
      );
      incomingReservation = reservation;
      final destination = reservation.destination;
      final partial = reservation.partial;
      partialFile = partial;

      final sink = partial.openWrite();
      uploadSink = sink;
      var received = 0;
      var nextDiskSpaceCheckAt = _incomingUploadDiskSpaceCheckIntervalBytes;
      final iterator = StreamIterator<List<int>>(request);
      uploadIterator = iterator;
      final timeoutSignal = Completer<String>();

      void reportTimeout(String reason) {
        if (!timeoutSignal.isCompleted) timeoutSignal.complete(reason);
      }

      void resetIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(
          incomingUploadIdleTimeout,
          () => reportTimeout('idle'),
        );
      }

      Never throwUploadTimeout(String reason) {
        if (reason == 'idle') {
          throw TimeoutException('Incoming audio upload was idle.');
        }
        throw const _IncomingUploadTotalTimeout();
      }

      resetIdleTimer();
      totalTimer = Timer(
        incomingUploadTotalTimeout,
        () => reportTimeout('total'),
      );

      while (true) {
        final move = iterator.moveNext();
        // Kept until the move resolves: a timeout can win the race below, and
        // the rejection drain must continue this pending read rather than
        // start a second one on the same iterator.
        pendingMoveNext = move;
        final event = await Future.any<Object>([
          move.then((hasNext) => _IncomingUploadChunkSignal(hasNext)),
          timeoutSignal.future.then(
            (reason) => _IncomingUploadTimeoutSignal(reason),
          ),
        ]);
        if (event is _IncomingUploadTimeoutSignal) {
          throwUploadTimeout(event.reason);
        }
        pendingMoveNext = null;
        if (timeoutSignal.isCompleted) {
          throwUploadTimeout(await timeoutSignal.future);
        }

        final chunkEvent = event as _IncomingUploadChunkSignal;
        if (!chunkEvent.hasNext) break;
        resetIdleTimer();
        final chunk = iterator.current;
        if (chunk.length > maxIncomingAudioBytes - received) {
          throw const _IncomingUploadTooLarge();
        }

        if (received + chunk.length >= nextDiskSpaceCheckAt) {
          final latestFreeBytes = await _availableDiskSpace(directory);
          if (timeoutSignal.isCompleted) {
            throwUploadTimeout(await timeoutSignal.future);
          }
          if (latestFreeBytes == null) {
            throw const _IncomingUploadStorageCheckUnavailable();
          }
          if (!_hasEnoughFreeSpace(latestFreeBytes, chunk.length)) {
            throw const _IncomingUploadInsufficientSpace();
          }
          nextDiskSpaceCheckAt =
              received +
              chunk.length +
              _incomingUploadDiskSpaceCheckIntervalBytes;
        }

        sink.add(chunk);
        received += chunk.length;
      }
      cancelUploadTimers();

      await sink.flush();
      await sink.close();
      uploadSink = null;

      if (expectedLength != null && received != expectedLength) {
        await releaseUploadResources();
        await _writeJson(request.response, HttpStatus.badRequest, {
          'error': 'length_mismatch',
          'expected': expectedLength,
          'received': received,
        });
        return;
      }

      await partial.rename(destination.path);
      partialFile = null;
      final callback = onIncomingFile;
      if (callback != null) {
        try {
          await callback(destination.path);
        } catch (error) {
          if (await destination.exists()) await destination.delete();
          await releaseUploadResources();
          await _writeJson(request.response, HttpStatus.internalServerError, {
            'error': 'library_import_failed',
            'message': error.toString(),
          });
          return;
        }
      }

      await releaseUploadResources();
      await _writeJson(request.response, HttpStatus.created, {
        'status': 'ok',
        'filename': destination.uri.pathSegments.last,
        'byteLength': received,
        'imported': callback != null,
      });
    } on _IncomingUploadTooLarge {
      await rejectInFlight(
        HttpStatus.requestEntityTooLarge,
        'upload_too_large',
        details: {'maxBytes': maxIncomingAudioBytes},
      );
    } on TimeoutException {
      await rejectInFlight(HttpStatus.requestTimeout, 'upload_idle_timeout');
    } on _IncomingUploadTotalTimeout {
      await rejectInFlight(HttpStatus.requestTimeout, 'upload_total_timeout');
    } on _IncomingUploadStorageCheckUnavailable {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'storage_check_unavailable',
      );
    } on _IncomingUploadInsufficientSpace {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'insufficient_storage',
        details: {'minimumFreeBytes': minimumFreeSpaceBytes},
      );
    } on FileSystemException {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'storage_write_failed',
      );
    } catch (_) {
      await releaseUploadResources();
      rethrow;
    } finally {
      await releaseUploadResources();
      try {
        await uploadIterator?.cancel();
      } catch (_) {
        // The request may already have been closed by the client.
      }
    }
  }

  bool _tryReserveIncomingUpload(String sessionToken) {
    if (_activeIncomingUploads >= _maximumConcurrentIncomingUploads ||
        !_activeIncomingSessionTokens.add(sessionToken)) {
      return false;
    }
    _activeIncomingUploads++;
    return true;
  }

  void _releaseIncomingUpload(String sessionToken) {
    if (_activeIncomingSessionTokens.remove(sessionToken)) {
      _activeIncomingUploads--;
    }
  }

  Future<int?> _availableDiskSpace(Directory directory) async {
    try {
      return await _diskSpaceProbe(directory);
    } catch (_) {
      return null;
    }
  }

  bool _hasEnoughFreeSpace(int availableBytes, int payloadBytes) {
    if (availableBytes < minimumFreeSpaceBytes) return false;
    return payloadBytes <= availableBytes - minimumFreeSpaceBytes;
  }

  Future<void> _rejectIncomingUpload(
    HttpRequest request,
    int statusCode,
    String errorCode, {
    Map<String, dynamic> details = const {},
    int? retryAfterSeconds,
    StreamIterator<List<int>>? body,
    Future<bool>? pendingMoveNext,
  }) async {
    final response = request.response;
    response.persistentConnection = false;
    if (retryAfterSeconds != null) {
      response.headers.set('Retry-After', retryAfterSeconds.toString());
    }
    final bytes = utf8.encode(jsonEncode({'error': errorCode, ...details}));
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.contentLength = bytes.length;
    response.add(bytes);
    try {
      // Send the answer first, then consume what the client is still sending
      // so closing does not reset the connection under an unread response.
      await response.flush();
      await _drainRejectedUploadBody(
        request,
        iterator: body,
        pendingMoveNext: pendingMoveNext,
      );
    } catch (_) {
      // The client may already have gone away; closing below still releases
      // the connection.
    }
    try {
      await response.close();
    } catch (_) {
      // Nothing is left to report to a client that disconnected.
    }
  }

  /// Reads and discards the rest of a rejected request body for at most
  /// [incomingRejectionDrainGrace] and [_maximumRejectedBodyDrainBytes].
  ///
  /// Uses [iterator] (continuing [pendingMoveNext] if a read is in flight)
  /// when the body was already being consumed; otherwise reads the request
  /// directly. Never stores the bytes.
  Future<void> _drainRejectedUploadBody(
    HttpRequest request, {
    StreamIterator<List<int>>? iterator,
    Future<bool>? pendingMoveNext,
  }) async {
    final grace = incomingRejectionDrainGrace;
    if (grace <= Duration.zero) return;
    final ownsIterator = iterator == null;
    final body = iterator ?? StreamIterator<List<int>>(request);
    final elapsed = Stopwatch()..start();
    var drained = 0;
    var next = pendingMoveNext;
    try {
      while (drained <= _maximumRejectedBodyDrainBytes) {
        final remaining = grace - elapsed.elapsed;
        if (remaining <= Duration.zero) break;
        final move = next ?? body.moveNext();
        next = null;
        final hasNext = await move.timeout(remaining, onTimeout: () => false);
        if (!hasNext) break;
        drained += body.current.length;
      }
    } catch (_) {
      // A client that disconnects mid-drain needs nothing more from us.
    } finally {
      if (ownsIterator) {
        try {
          await body.cancel();
        } catch (_) {}
      }
    }
  }

  Future<void> _discardPartialUpload(IOSink? sink, File? partial) async {
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {}
    }
    if (partial != null) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
    }
  }

  Future<Directory> _resolveIncomingDirectory() async {
    final configured = incomingDirectory;
    if (configured != null) return configured;
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Incoming',
    );
  }

  Future<_IncomingUploadReservation> _reserveIncomingDestination(
    Directory directory,
    String fileName,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var suffix = 0;

    while (true) {
      final candidateName = suffix == 0
          ? fileName
          : '${stem}_$suffix$extension';
      final candidate = File(
        '${directory.path}${Platform.pathSeparator}$candidateName',
      );
      suffix++;

      if (await candidate.exists()) continue;

      // Exclusive marker creation serializes destination selection for
      // concurrent uploads without relying on a process-local lock.
      final reservation = File('${candidate.path}.reserve');
      try {
        await reservation.create(exclusive: true);
      } on FileSystemException {
        if (await reservation.exists()) continue;
        rethrow;
      }

      try {
        // Recheck after claiming the marker in case another writer that does
        // not use reservations created the final file between the first check
        // and the exclusive marker creation.
        if (await candidate.exists()) {
          await _releaseReservationFile(reservation);
          continue;
        }
        final partial = await _createUniqueIncomingPartial(directory);
        return _IncomingUploadReservation(
          destination: candidate,
          partial: partial,
          reservationFile: reservation,
        );
      } catch (_) {
        await _releaseReservationFile(reservation);
        rethrow;
      }
    }
  }

  Future<File> _createUniqueIncomingPartial(Directory directory) async {
    while (true) {
      final partial = File(
        '${directory.path}${Platform.pathSeparator}.lyricforge-${_uuid.v4()}.part',
      );
      try {
        await partial.create(exclusive: true);
        return partial;
      } on FileSystemException {
        if (await partial.exists()) continue;
        rethrow;
      }
    }
  }

  Future<void> _releaseIncomingDestinationReservation(
    _IncomingUploadReservation reservation,
  ) async {
    await _releaseReservationFile(reservation.reservationFile);
  }

  Future<void> _releaseReservationFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale marker is safer than allowing another upload to reuse a name
      // that may still be in the process of being committed or imported.
    }
  }

  String _safeIncomingName(String value) {
    var name = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    return name.isEmpty ? 'audio' : name;
  }

  Future<void> _serveArtwork(
    HttpRequest request,
    SharedAudioTrack track,
  ) async {
    final path = track.artworkPath;
    if (path == null || path.trim().isEmpty) {
      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'artwork_not_found',
      });
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      await _writeJson(request.response, HttpStatus.gone, {
        'error': 'artwork_missing',
      });
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.parse(
      _imageMimeTypeFor(path),
    );
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, max-age=3600',
    );
    request.response.contentLength = await file.length();
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> _serveAudio(HttpRequest request, SharedAudioTrack track) async {
    final file = File(track.localPath);
    if (!await file.exists()) {
      await _writeJson(request.response, HttpStatus.gone, {
        'error': 'source_file_missing',
      });
      return;
    }

    final length = await file.length();
    final parsed = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );

    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType = ContentType.parse(
      _mimeTypeFor(track.format),
    );
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'private, no-store',
    );

    if (!parsed.isValid) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$length',
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
      'bytes ${range.start}-${range.endInclusive}/$length',
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

  String _imageMimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
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
      return _ParsedRange.valid(_ByteRange(length - clamped, length - 1));
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

/// PowerShell script used by [_probeAvailableDiskSpaceBytes] on Windows.
///
/// The upload directory is passed through the `LYRICFORGE_UPLOAD_PATH`
/// environment variable so the path never needs shell quoting. The script
/// prints the available free bytes of the drive that holds the directory and
/// exits with code 3 when the path root is not a drive-letter root.
///
/// Kept as a named constant (instead of an inline literal) so
/// `media_hub_disk_space_probe_contract_test.dart` can pin its exact content
/// and execute it under real PowerShell on Windows CI. A corrupted copy of
/// this script once shipped inside the string literal and silently broke
/// every Windows incoming upload with 507 responses (issue #255).
const String mediaHubWindowsDiskSpaceProbeScript = r'''
$path = $env:LYRICFORGE_UPLOAD_PATH
$root = [System.IO.Path]::GetPathRoot($path)
if ($root -notmatch '^[A-Za-z]:\\$') { exit 3 }
$drive = New-Object System.IO.DriveInfo -ArgumentList $root
[Console]::Out.Write([string]$drive.AvailableFreeSpace)''';

Future<int?> _probeAvailableDiskSpaceBytes(Directory directory) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          mediaHubWindowsDiskSpaceProbeScript,
        ],
        environment: {'LYRICFORGE_UPLOAD_PATH': directory.absolute.path},
      );
      if (result.exitCode != 0) return null;
      final freeBytes = int.tryParse(result.stdout.toString().trim());
      return freeBytes != null && freeBytes >= 0 ? freeBytes : null;
    }

    if (!Platform.isLinux && !Platform.isMacOS) return null;

    final result = await Process.run('df', ['-Pk', directory.absolute.path]);
    if (result.exitCode != 0) return null;
    final lines = result.stdout
        .toString()
        .trim()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    final availableBlocks = int.tryParse(columns[3]);
    if (availableBlocks == null ||
        availableBlocks < 0 ||
        availableBlocks > 0x7fffffffffffffff ~/ 1024) {
      return null;
    }
    return availableBlocks * 1024;
  } catch (_) {
    return null;
  }
}

class _IncomingUploadChunkSignal {
  const _IncomingUploadChunkSignal(this.hasNext);

  final bool hasNext;
}

class _IncomingUploadTimeoutSignal {
  const _IncomingUploadTimeoutSignal(this.reason);

  final String reason;
}

class _IncomingUploadTooLarge implements Exception {
  const _IncomingUploadTooLarge();
}

class _IncomingUploadTotalTimeout implements Exception {
  const _IncomingUploadTotalTimeout();
}

class _IncomingUploadStorageCheckUnavailable implements Exception {
  const _IncomingUploadStorageCheckUnavailable();
}

class _IncomingUploadInsufficientSpace implements Exception {
  const _IncomingUploadInsufficientSpace();
}

class _IncomingUploadReservation {
  const _IncomingUploadReservation({
    required this.destination,
    required this.partial,
    required this.reservationFile,
  });

  final File destination;
  final File partial;
  final File reservationFile;
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

class _ByteRange {
  final int start;
  final int endInclusive;

  const _ByteRange(this.start, this.endInclusive);

  int get length => endInclusive - start + 1;
}

class _ParsedRange {
  final bool isValid;
  final _ByteRange? range;

  const _ParsedRange.none() : isValid = true, range = null;

  const _ParsedRange.invalid() : isValid = false, range = null;

  const _ParsedRange.valid(this.range) : isValid = true;
}
