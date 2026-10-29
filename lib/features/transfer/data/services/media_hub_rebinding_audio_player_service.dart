import 'dart:async';
import 'dart:io';

import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import 'media_hub_tls_identity_store.dart';

/// Guarantees that every Media Hub audio load uses the latest usable connection
/// known to the app, including loads triggered internally by automatic queue
/// advance.
///
/// Non-Media-Hub HTTP audio and local/project audio pass through unchanged.
class _MediaHubProxyTarget {
  final MediaHubConnection connection;
  final Uri remoteUri;

  const _MediaHubProxyTarget({required this.connection, required this.remoteUri});
}

class MediaHubRebindingAudioPlayerService implements AudioPlayerService {
  final AudioPlayerService delegate;
  final MediaHubClientService client;
  final MediaHubConnectionStore connectionStore;
  final Uuid _uuid = const Uuid();
  HttpServer? _proxyServer;
  final Map<String, _MediaHubProxyTarget> _proxyTargets =
      <String, _MediaHubProxyTarget>{};
  String? _activeProxyPath;

  MediaHubRebindingAudioPlayerService({
    required this.delegate,
    required this.client,
    required this.connectionStore,
  });

  @override
  PlaybackState get currentState => delegate.currentState;

  @override
  Stream<PlaybackState> get stateStream => delegate.stateStream;

  @override
  Stream<Duration> get positionStream => delegate.positionStream;

  @override
  Stream<Duration?> get durationStream => delegate.durationStream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) =>
      delegate.loadProjectAudio(
        audioAsset: audioAsset,
        preferredSource: preferredSource,
      );

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    final resolved = await _latestMediaHubUri(uri);
    if (_looksLikeMediaHubAudio(resolved)) {
      final connection = client.currentConnection;
      if (connection == null) {
        throw StateError('Media Hub 未连接，无法安全播放远程音频');
      }
      final proxyPath = await _registerProxyTarget(resolved, connection);
      final server = _proxyServer!;
      final proxyUri = Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: proxyPath,
      );
      try {
        await delegate.loadAudioUri(uri: proxyUri, source: source);
        _activeProxyPath = proxyPath;
        _proxyTargets.removeWhere((path, _) => path != proxyPath);
      } catch (_) {
        _proxyTargets.remove(proxyPath);
        rethrow;
      }
      return;
    }
    await delegate.loadAudioUri(uri: resolved, source: source);
    _proxyTargets.clear();
    _activeProxyPath = null;
  }

  Future<String> _registerProxyTarget(
    Uri uri,
    MediaHubConnection connection,
  ) async {
    if (connection.tlsFingerprint == null ||
        !RegExp(r'^[0-9a-fA-F]{64}

  Future<Uri> _latestMediaHubUri(Uri original) async {
    if (!_looksLikeMediaHubAudio(original)) return original;

    final active = client.currentConnection;
    final saved = await connectionStore.loadLastConnection();
    final candidates = <MediaHubConnection>[];
    if (active != null) candidates.add(active);
    if (saved != null &&
        (active == null || !_sameConnection(active, saved))) {
      candidates.add(saved);
    }

    if (candidates.isEmpty) return original;

    Object? lastError;
    for (final connection in candidates) {
      try {
        // connectTo may transparently replace a stale endpoint through the UDP
        // device discovery flow. Always rebase with the connection it actually
        // resolved, not the stale candidate passed into this call.
        await client.connectTo(connection);
        final resolvedConnection = client.currentConnection ?? connection;
        return _rebase(original, resolvedConnection);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError;
    return original;
  }

  bool _sameConnection(MediaHubConnection a, MediaHubConnection b) =>
      a.host == b.host && a.port == b.port && a.token == b.token;

  bool _looksLikeMediaHubAudio(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'tracks' &&
        segments.last == 'audio';
  }

  Uri _rebase(Uri original, MediaHubConnection connection) {
    final rebased = connection.resolve(original.path);
    return rebased.replace(
      queryParameters: {
        ...original.queryParameters,
        'token': connection.token,
      },
    );
  }

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> switchSource(AudioSourceType source) =>
      delegate.switchSource(source);

  @override
  Future<void> setSpeed(double speed) => delegate.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => delegate.setVolume(volume);

  @override
  Future<void> dispose() async {
    _proxyTargets.clear();
    _activeProxyPath = null;
    await _proxyServer?.close(force: true);
    _proxyServer = null;
    _proxyListening = false;
    await delegate.dispose();
  }
}
).hasMatch(connection.tlsFingerprint!)) {
      throw StateError('Media Hub 连接缺少有效 TLS 指纹，请重新配对');
    }
    final server = _proxyServer ??= await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final path = '/play/${_uuid.v4()}';
    _proxyTargets[path] = _MediaHubProxyTarget(
      connection: connection,
      remoteUri: uri.replace(queryParameters: _withoutToken(uri.queryParameters)),
    );
    // Start the loopback handler once; it forwards only opaque, per-load paths.
    if (!_proxyListening) {
      _proxyListening = true;
      server.listen((request) => unawaited(_handleProxyRequest(request)));
    }
    return path;
  }

  bool _proxyListening = false;

  Map<String, String> _withoutToken(Map<String, String> parameters) {
    final result = Map<String, String>.from(parameters)..remove('token');
    return result;
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    final target = _proxyTargets[request.uri.path];
    if (target == null ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final pin = target.connection.tlsFingerprint!.toLowerCase();
    final httpClient = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    httpClient.badCertificateCallback = (certificate, host, port) =>
        mediaHubTlsFingerprint(certificate.der) == pin;
    try {
      final upstream = await httpClient.openUrl(request.method, target.remoteUri);
      upstream.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${target.connection.token}',
      );
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
      final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
      if (ifRange != null) upstream.headers.set(HttpHeaders.ifRangeHeader, ifRange);

      final response = await upstream.close();
      request.response.statusCode = response.statusCode;
      final contentType = response.headers.contentType;
      if (contentType != null) request.response.headers.contentType = contentType;
      if (response.contentLength >= 0) {
        request.response.contentLength = response.contentLength;
      }
      for (final header in <String>[
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.cacheControlHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final value = response.headers.value(header);
        if (value != null) request.response.headers.set(header, value);
      }
      if (request.method == 'HEAD') {
        await response.drain<void>();
      } else {
        await request.response.addStream(response);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<Uri> _latestMediaHubUri(Uri original) async {
    if (!_looksLikeMediaHubAudio(original)) return original;

    final active = client.currentConnection;
    final saved = await connectionStore.loadLastConnection();
    final candidates = <MediaHubConnection>[];
    if (active != null) candidates.add(active);
    if (saved != null &&
        (active == null || !_sameConnection(active, saved))) {
      candidates.add(saved);
    }

    if (candidates.isEmpty) return original;

    Object? lastError;
    for (final connection in candidates) {
      try {
        // connectTo may transparently replace a stale endpoint through the UDP
        // device discovery flow. Always rebase with the connection it actually
        // resolved, not the stale candidate passed into this call.
        await client.connectTo(connection);
        final resolvedConnection = client.currentConnection ?? connection;
        return _rebase(original, resolvedConnection);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError;
    return original;
  }

  bool _sameConnection(MediaHubConnection a, MediaHubConnection b) =>
      a.host == b.host && a.port == b.port && a.token == b.token;

  bool _looksLikeMediaHubAudio(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'tracks' &&
        segments.last == 'audio';
  }

  Uri _rebase(Uri original, MediaHubConnection connection) {
    final rebased = connection.resolve(original.path);
    return rebased.replace(
      queryParameters: {
        ...original.queryParameters,
        'token': connection.token,
      },
    );
  }

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> switchSource(AudioSourceType source) =>
      delegate.switchSource(source);

  @override
  Future<void> setSpeed(double speed) => delegate.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => delegate.setVolume(volume);

  @override
  Future<void> dispose() => delegate.dispose();
}
