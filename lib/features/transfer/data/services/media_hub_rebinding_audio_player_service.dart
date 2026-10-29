import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';
import 'media_hub_tls_identity_store.dart';

/// A short-lived local URL bound to one certificate-pinned Media Hub target.
/// Native audio engines use the loopback URL, while credentials stay in the
/// Authorization header on the HTTPS hop.
class _MediaHubProxyTarget {
  final MediaHubConnection connection;
  final Uri remoteUri;

  const _MediaHubProxyTarget({
    required this.connection,
    required this.remoteUri,
  });
}

/// Rebinds restored Media Hub stream URLs to the current connection.
///
/// Media Hub audio is proxied through loopback because native audio playback
/// adapters cannot be configured with this app's per-connection certificate
/// pin. The proxy is loopback-only, strips query credentials and preserves
/// HTTP Range semantics while authenticating the upstream HTTPS request.
class MediaHubRebindingAudioPlayerService implements AudioPlayerService {
  final AudioPlayerService delegate;
  final MediaHubClientService client;
  final MediaHubConnectionStore connectionStore;
  final Uuid _uuid = const Uuid();

  HttpServer? _proxyServer;
  bool _proxyListening = false;
  final Map<String, _MediaHubProxyTarget> _proxyTargets =
      <String, _MediaHubProxyTarget>{};

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
  }) async {
    await delegate.loadProjectAudio(
      audioAsset: audioAsset,
      preferredSource: preferredSource,
    );
    _proxyTargets.clear();
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    final resolved = await _latestMediaHubUri(uri);
    if (!_looksLikeMediaHubAudio(resolved)) {
      await delegate.loadAudioUri(uri: resolved, source: source);
      _proxyTargets.clear();
      return;
    }

    final connection = client.currentConnection;
    if (connection == null) {
      throw StateError('Media Hub 未连接，无法安全播放远程音频');
    }

    final path = await _registerProxyTarget(resolved, connection);
    final proxy = _proxyServer!;
    final localUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: proxy.port,
      path: path,
    );

    try {
      await delegate.loadAudioUri(uri: localUri, source: source);
      _proxyTargets.removeWhere((key, _) => key != path);
    } catch (_) {
      _proxyTargets.remove(path);
      rethrow;
    }
  }

  Future<String> _registerProxyTarget(
    Uri remoteUri,
    MediaHubConnection connection,
  ) async {
    final fingerprint = connection.tlsFingerprint;
    if (fingerprint == null ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(fingerprint)) {
      throw StateError('Media Hub 连接缺少有效 TLS 指纹，请重新配对');
    }

    final server = _proxyServer ??= await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final path = '/play/${_uuid.v4()}';
    final query = Map<String, String>.from(remoteUri.queryParameters)
      ..remove('token');
    final upstreamUri = query.isEmpty
        ? remoteUri.replace(queryParameters: <String, String>{})
        : remoteUri.replace(queryParameters: query);

    _proxyTargets[path] = _MediaHubProxyTarget(
      connection: connection,
      remoteUri: upstreamUri,
    );

    if (!_proxyListening) {
      _proxyListening = true;
      server.listen((request) => unawaited(_handleProxyRequest(request)));
    }
    return path;
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    final target = _proxyTargets[request.uri.path];
    if (target == null ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fingerprint = target.connection.tlsFingerprint;
    if (fingerprint == null) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    final upstreamClient = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    upstreamClient.badCertificateCallback = (certificate, host, port) =>
        mediaHubTlsFingerprint(certificate.der) == fingerprint.toLowerCase();

    try {
      final upstreamRequest =
          await upstreamClient.openUrl(request.method, target.remoteUri);
      upstreamRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${target.connection.token}',
      );

      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
      }
      final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
      if (ifRange != null) {
        upstreamRequest.headers.set(HttpHeaders.ifRangeHeader, ifRange);
      }

      final upstreamResponse = await upstreamRequest.close();
      request.response.statusCode = upstreamResponse.statusCode;
      final contentType = upstreamResponse.headers.contentType;
      if (contentType != null) {
        request.response.headers.contentType = contentType;
      }
      if (upstreamResponse.contentLength >= 0) {
        request.response.contentLength = upstreamResponse.contentLength;
      }

      for (final header in <String>[
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.cacheControlHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final value = upstreamResponse.headers.value(header);
        if (value != null) request.response.headers.set(header, value);
      }

      if (request.method == 'HEAD') {
        await upstreamResponse.drain<void>();
      } else {
        await request.response.addStream(upstreamResponse);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {
        // A client may have disconnected while the upstream request failed.
      }
    } finally {
      upstreamClient.close(force: true);
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

    if (candidates.isEmpty) {
      throw StateError('没有已配对的 Media Hub 连接，请重新扫码');
    }

    Object? lastError;
    for (final connection in candidates) {
      try {
        await client.connectTo(connection);
        final current = client.currentConnection;
        if (current == null) {
          throw StateError('Media Hub 未返回有效连接');
        }
        return _rebase(original, current);
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError('无法安全重新连接 Media Hub：$lastError');
  }

  bool _sameConnection(MediaHubConnection a, MediaHubConnection b) =>
      a.host == b.host &&
      a.port == b.port &&
      a.token == b.token &&
      a.tlsFingerprint == b.tlsFingerprint;

  bool _looksLikeMediaHubAudio(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'tracks' &&
        segments.last == 'audio';
  }

  Uri _rebase(Uri original, MediaHubConnection connection) {
    final query = Map<String, String>.from(original.queryParameters)
      ..remove('token');
    final target = connection.resolve(original.path);
    return query.isEmpty ? target : target.replace(queryParameters: query);
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
    await _proxyServer?.close(force: true);
    _proxyServer = null;
    _proxyListening = false;
    await delegate.dispose();
  }
}
