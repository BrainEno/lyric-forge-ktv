import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_session.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_tls_identity_store.dart';

void main() {
  late Directory temp;
  late Directory incomingDirectory;
  late HttpMediaHubService service;
  final imported = <String>[];

  HttpMediaHubService createService({
    int maxIncomingAudioBytes =
        HttpMediaHubService.defaultMaxIncomingAudioBytes,
    Duration idleTimeout = HttpMediaHubService.defaultIncomingUploadIdleTimeout,
    Duration totalTimeout =
        HttpMediaHubService.defaultIncomingUploadTotalTimeout,
    int minimumFreeSpaceBytes = 0,
    IncomingDiskSpaceProbe? diskSpaceProbe,
    IncomingMediaCallback? onIncomingFile,
  }) {
    return HttpMediaHubService(
      incomingDirectory: incomingDirectory,
      tlsIdentityStore: MediaHubTlsIdentityStore(
        rootDirectory: Directory(temp.path + Platform.pathSeparator + 'tls'),
      ),
      maxIncomingAudioBytes: maxIncomingAudioBytes,
      incomingUploadIdleTimeout: idleTimeout,
      incomingUploadTotalTimeout: totalTimeout,
      minimumFreeSpaceBytes: minimumFreeSpaceBytes,
      diskSpaceProbe:
          diskSpaceProbe ?? (Directory _) async => 8 * 1024 * 1024 * 1024,
      onIncomingFile:
          onIncomingFile ??
          (path) async {
            imported.add(path);
          },
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lyricforge-incoming-');
    incomingDirectory = Directory(
      temp.path + Platform.pathSeparator + 'incoming',
    );
    imported.clear();
    service = createService();
  });

  tearDown(() async {
    await service.stopSharing();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'empty share list starts receive-only hub and imports complete upload',
    () async {
      final session = await service.startSharing(const []);
      expect(session.trackCount, 0);

      final client = _pinnedHttpClient(session.tlsFingerprint!);
      addTearDown(() => client.close(force: true));
      final uri = Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/incoming/audio',
        queryParameters: const {'filename': '测试歌曲.mp3'},
      );
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.token}',
      );
      final bytes = utf8.encode('fake mp3 bytes');
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      expect(response.statusCode, HttpStatus.created);
      expect(body, contains('测试歌曲.mp3'));
      expect(imported, hasLength(1));
      final received = File(imported.single);
      expect(await received.exists(), isTrue);
      expect(await received.readAsBytes(), bytes);
      expect(await File('${received.path}.part').exists(), isFalse);
    },
  );

  test('real client uploads a local file to receive-only hub', () async {
    final session = await service.startSharing(const []);
    final sourceDir = await Directory.systemTemp.createTemp(
      'lyricforge-upload-source-',
    );
    addTearDown(() async {
      if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
    });
    final source = File('${sourceDir.path}${Platform.pathSeparator}手机歌曲.flac');
    final bytes = List<int>.generate(48 * 1024, (index) => index % 239);
    await source.writeAsBytes(bytes);

    final client = HttpMediaHubClientService();
    addTearDown(client.dispose);
    await client.connectTo(
      MediaHubConnection(
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        token: session.token,
        tlsFingerprint: session.tlsFingerprint,
        transport: MediaHubTransport.lan,
      ),
    );

    var progressCalls = 0;
    await client.uploadFile(
      sourcePath: source.path,
      onProgress: (transferred, total) {
        progressCalls++;
        expect(transferred, lessThanOrEqualTo(bytes.length));
        expect(total, bytes.length);
      },
    );

    expect(progressCalls, greaterThan(0));
    expect(imported, hasLength(1));
    expect(await File(imported.single).readAsBytes(), bytes);
  });

  test('query token cannot authorize an upload', () async {
    final session = await service.startSharing(const []);
    final client = _pinnedHttpClient(session.tlsFingerprint!);
    addTearDown(() => client.close(force: true));
    final uri = Uri(
      scheme: 'https',
      host: InternetAddress.loopbackIPv4.address,
      port: session.port,
      path: '/v1/incoming/audio',
      queryParameters: {'filename': 'blocked.mp3', 'token': session.token},
    );
    final request = await client.postUrl(uri);
    request.contentLength = 3;
    request.add(const [1, 2, 3]);

    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(imported, isEmpty);
    expect(await incomingDirectory.exists(), isFalse);
  });

  test('browser preflight is not granted cross-origin access', () async {
    final session = await service.startSharing(const []);
    final client = _pinnedHttpClient(session.tlsFingerprint!);
    addTearDown(() => client.close(force: true));

    final request = await client.openUrl(
      'OPTIONS',
      Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/health',
      ),
    );
    request.headers.set('Origin', 'https://attacker.example');
    request.headers.set('Access-Control-Request-Method', 'GET');
    request.headers.set('Access-Control-Request-Headers', 'Authorization');

    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(response.headers.value('Access-Control-Allow-Origin'), isNull);
    expect(response.headers.value('Access-Control-Allow-Headers'), isNull);
    expect(response.headers.value('Access-Control-Allow-Methods'), isNull);
  });

  test(
    'concurrent same-name uploads preserve both complete file hashes',
    () async {
      final secondService = createService();
      addTearDown(secondService.stopSharing);
      final sessionA = await service.startSharing(const []);
      final sessionB = await secondService.startSharing(const []);
      expect(sessionA.token, isNot(sessionB.token));

      final clientA = _pinnedHttpClient(sessionA.tlsFingerprint!);
      final clientB = _pinnedHttpClient(sessionB.tlsFingerprint!);
      addTearDown(() => clientA.close(force: true));
      addTearDown(() => clientB.close(force: true));

      final bytesA = List<int>.generate(
        256 * 1024,
        (index) => (index * 17) % 251,
      );
      final bytesB = List<int>.generate(
        256 * 1024,
        (index) => (index * 29 + 7) % 253,
      );

      Future<Map<String, dynamic>> upload(
        HttpClient client,
        MediaHubSession session,
        List<int> bytes,
      ) async {
        final request = await client.postUrl(
          Uri(
            scheme: 'https',
            host: InternetAddress.loopbackIPv4.address,
            port: session.port,
            path: '/v1/incoming/audio',
            queryParameters: const {'filename': 'same-name.mp3'},
          ),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.token}',
        );
        request.contentLength = bytes.length;
        request.add(bytes);

        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        final body =
            jsonDecode(await utf8.decoder.bind(response).join())
                as Map<String, dynamic>;
        expect(response.statusCode, HttpStatus.created);
        return body;
      }

      final bodies = await Future.wait([
        upload(clientA, sessionA, bytesA),
        upload(clientB, sessionB, bytesB),
      ]);
      expect(bodies.map((body) => body['filename']).toSet(), {
        'same-name.mp3',
        'same-name_1.mp3',
      });
      expect(imported, hasLength(2));
      expect(imported.toSet(), hasLength(2));

      final actualHashes = <String>{};
      for (final path in imported) {
        actualHashes.add(
          sha256.convert(await File(path).readAsBytes()).toString(),
        );
      }
      expect(actualHashes, {
        sha256.convert(bytesA).toString(),
        sha256.convert(bytesB).toString(),
      });

      final leftovers = await incomingDirectory
          .list()
          .where(
            (entity) =>
                entity.path.endsWith('.part') ||
                entity.path.endsWith('.reserve'),
          )
          .toList();
      expect(leftovers, isEmpty);
      await secondService.stopSharing();
    },
  );

  test('failed library import removes the completed incoming file', () async {
    await service.stopSharing();
    service = createService(
      onIncomingFile: (_) async {
        throw UnsupportedError('unsupported audio');
      },
    );
    final session = await service.startSharing(const []);

    final client = _pinnedHttpClient(session.tlsFingerprint!);
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(
      Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/incoming/audio',
        queryParameters: const {'filename': 'not-audio.txt'},
      ),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.token}',
    );
    request.contentLength = 4;
    request.add(const [1, 2, 3, 4]);

    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(await incomingDirectory.list().toList(), isEmpty);
  });

  test(
    'rejects declared uploads above the configured cap before creating storage',
    () async {
      service = createService(maxIncomingAudioBytes: 4);
      final session = await service.startSharing(const []);
      final socket = await _openPinnedSocket(session);
      addTearDown(socket.destroy);
      final responseFuture = _readRawResponse(socket);
      socket.write(
        _rawContentLengthHeaders(session, 'too-big.bin', 5) + '12345',
      );
      await socket.flush();

      final response = await responseFuture;
      expect(response, startsWith('HTTP/1.1 413'));
      expect(response, contains('upload_too_large'));
      expect(await incomingDirectory.exists(), isFalse);
    },
  );

  test(
    'rejects chunked uploads above the cap and deletes the partial file',
    () async {
      service = createService(maxIncomingAudioBytes: 4);
      final session = await service.startSharing(const []);
      final socket = await _openPinnedSocket(session);
      addTearDown(socket.destroy);
      final responseFuture = _readRawResponse(socket);
      socket.write(
        _rawChunkedHeaders(session, 'chunked-too-big.bin') +
            '5\r\n12345\r\n0\r\n\r\n',
      );
      await socket.flush();

      final response = await responseFuture;
      expect(response, startsWith('HTTP/1.1 413'));
      expect(response, contains('upload_too_large'));
      expect(await incomingDirectory.list().toList(), isEmpty);
    },
  );

  test('rejects upload when disk space cannot preserve the reserve', () async {
    service = createService(
      minimumFreeSpaceBytes: 100,
      diskSpaceProbe: (Directory _) async => 103,
    );
    final session = await service.startSharing(const []);
    final socket = await _openPinnedSocket(session);
    addTearDown(socket.destroy);
    final responseFuture = _readRawResponse(socket);
    socket.write(
      _rawContentLengthHeaders(session, 'low-space.bin', 4) + 'data',
    );
    await socket.flush();

    final response = await responseFuture;
    expect(response, startsWith('HTTP/1.1 507'));
    expect(response, contains('insufficient_storage'));
    expect(await incomingDirectory.list().toList(), isEmpty);
  });

  test('rejects uploads when disk-space information is unavailable', () async {
    service = createService(diskSpaceProbe: (Directory _) async => null);
    final session = await service.startSharing(const []);
    final socket = await _openPinnedSocket(session);
    addTearDown(socket.destroy);
    final responseFuture = _readRawResponse(socket);
    socket.write(
      _rawContentLengthHeaders(session, 'unknown-space.bin', 4) + 'data',
    );
    await socket.flush();

    final response = await responseFuture;
    expect(response, startsWith('HTTP/1.1 507'));
    expect(response, contains('storage_check_unavailable'));
    expect(await incomingDirectory.list().toList(), isEmpty);
  });

  test('idle upload timeout removes the partial file', () async {
    service = createService(
      maxIncomingAudioBytes: 64,
      idleTimeout: const Duration(milliseconds: 150),
      totalTimeout: const Duration(seconds: 3),
    );
    final session = await service.startSharing(const []);
    final socket = await _openPinnedSocket(session);
    addTearDown(socket.destroy);
    final responseFuture = _readRawResponse(socket);
    socket.write(
      _rawChunkedHeaders(session, 'idle-timeout.bin') + '1\r\nx\r\n',
    );
    await socket.flush();

    final response = await responseFuture;
    expect(response, startsWith('HTTP/1.1 408'));
    expect(response, contains('upload_idle_timeout'));
    expect(await incomingDirectory.list().toList(), isEmpty);
  });

  test(
    'total upload deadline applies while chunks continue arriving',
    () async {
      service = createService(
        maxIncomingAudioBytes: 1024,
        idleTimeout: const Duration(seconds: 2),
        totalTimeout: const Duration(milliseconds: 250),
      );
      final session = await service.startSharing(const []);
      final socket = await _openPinnedSocket(session);
      addTearDown(socket.destroy);
      // Watch the response instead of only its completion: the server closes
      // the connection as soon as it rejects the upload, and a write that
      // lands after that teardown resets the connection and throws away a
      // response the client had already received.
      final reader = _RawResponseReader(socket);
      socket.write(
        _rawChunkedHeaders(session, 'total-timeout.bin') + '1\r\nx\r\n',
      );
      await socket.flush();

      for (var index = 0; index < 40 && !reader.hasStarted; index++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        if (reader.hasStarted) break;
        try {
          socket.write('1\r\nx\r\n');
          await socket.flush();
        } on SocketException {
          break;
        } on TlsException {
          break;
        }
      }

      final response = await reader.response.timeout(
        const Duration(seconds: 5),
      );
      expect(response, startsWith('HTTP/1.1 408'));
      expect(response, contains('upload_total_timeout'));
      expect(await incomingDirectory.list().toList(), isEmpty);
    },
  );

  test('rejects a second simultaneous upload for the same session', () async {
    final probeStarted = Completer<void>();
    service = createService(
      diskSpaceProbe: (Directory _) async {
        if (!probeStarted.isCompleted) probeStarted.complete();
        return 8 * 1024 * 1024 * 1024;
      },
    );
    final session = await service.startSharing(const []);
    final socket = await _openPinnedSocket(session);
    addTearDown(socket.destroy);
    final firstResponseFuture = _readRawResponse(socket);
    socket.write(_rawChunkedHeaders(session, 'first.bin') + '1\r\nx\r\n');
    await socket.flush();
    await probeStarted.future.timeout(const Duration(seconds: 2));

    final client = _pinnedHttpClient(session.tlsFingerprint!);
    addTearDown(() => client.close(force: true));
    final rejectedRequest = await client.postUrl(
      Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/incoming/audio',
        queryParameters: const {'filename': 'rejected.bin'},
      ),
    );
    rejectedRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.token}',
    );
    rejectedRequest.contentLength = 0;
    final rejectedResponse = await rejectedRequest.close();
    final rejectedBody = await utf8.decoder.bind(rejectedResponse).join();
    expect(rejectedResponse.statusCode, HttpStatus.tooManyRequests);
    expect(rejectedResponse.headers.value('retry-after'), '5');
    expect(rejectedBody, contains('upload_limit_reached'));

    socket.write('0\r\n\r\n');
    await socket.flush();
    final firstResponse = await firstResponseFuture;
    expect(firstResponse, startsWith('HTTP/1.1 201'));

    final retryRequest = await client.postUrl(
      Uri(
        scheme: 'https',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/incoming/audio',
        queryParameters: const {'filename': 'retry.bin'},
      ),
    );
    retryRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.token}',
    );
    retryRequest.contentLength = 1;
    retryRequest.add(const [1]);
    final retryResponse = await retryRequest.close();
    await retryResponse.drain<void>();
    expect(retryResponse.statusCode, HttpStatus.created);
  });
}

Future<SecureSocket> _openPinnedSocket(MediaHubSession session) {
  return SecureSocket.connect(
    InternetAddress.loopbackIPv4.address,
    session.port,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (certificate) =>
        mediaHubTlsFingerprint(certificate.der) ==
        session.tlsFingerprint!.toLowerCase(),
  );
}

Future<String> _readRawResponse(SecureSocket socket) {
  return socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .join()
      .timeout(const Duration(seconds: 5));
}

/// Reads a raw HTTP response while reporting the moment its first byte lands.
///
/// Tests that keep writing request body bytes until the server answers need to
/// know when the answer *starts*, not when it finishes: the hub closes the
/// connection while rejecting an upload, so a later client write can reset the
/// connection and discard bytes that already arrived. Such a reset is tolerated
/// once the response has started, because the response did reach the client; an
/// error before the first byte still fails the test.
class _RawResponseReader {
  _RawResponseReader(SecureSocket socket) {
    _subscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
          (text) {
            _buffer.write(text);
            _hasStarted = true;
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_hasStarted) {
              if (!_response.isCompleted) {
                _response.completeError(error, stackTrace);
              }
              return;
            }
            _subscription?.cancel();
            if (!_response.isCompleted) _response.complete(_buffer.toString());
          },
          onDone: () {
            if (!_response.isCompleted) _response.complete(_buffer.toString());
          },
          cancelOnError: true,
        );
  }

  final StringBuffer _buffer = StringBuffer();
  final Completer<String> _response = Completer<String>();
  StreamSubscription<String>? _subscription;
  bool _hasStarted = false;

  /// Whether at least one byte of the response has been received.
  bool get hasStarted => _hasStarted;

  /// The response text; resolves early (with what arrived) if the connection is
  /// reset after the response started.
  Future<String> get response => _response.future;
}

String _rawContentLengthHeaders(
  MediaHubSession session,
  String filename,
  int length,
) {
  return 'POST /v1/incoming/audio?filename=${Uri.encodeQueryComponent(filename)} HTTP/1.1\r\n'
      'Host: 127.0.0.1:${session.port}\r\n'
      'Authorization: Bearer ${session.token}\r\n'
      'Content-Length: $length\r\n'
      'Connection: close\r\n\r\n';
}

String _rawChunkedHeaders(MediaHubSession session, String filename) {
  return 'POST /v1/incoming/audio?filename=${Uri.encodeQueryComponent(filename)} HTTP/1.1\r\n'
      'Host: 127.0.0.1:${session.port}\r\n'
      'Authorization: Bearer ${session.token}\r\n'
      'Transfer-Encoding: chunked\r\n'
      'Connection: close\r\n\r\n';
}

HttpClient _pinnedHttpClient(String fingerprint) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.badCertificateCallback = (certificate, host, port) =>
      mediaHubTlsFingerprint(certificate.der) == fingerprint.toLowerCase();
  return client;
}
