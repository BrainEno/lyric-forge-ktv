import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    Duration idleTimeout =
        HttpMediaHubService.defaultIncomingUploadIdleTimeout,
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
          diskSpaceProbe ??
          (Directory _) async => 8 * 1024 * 1024 * 1024,
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
        'Bearer ' + session.token,
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

  test('unauthorized upload is rejected before a file is created', () async {
    final session = await service.startSharing(const []);
    final client = _pinnedHttpClient(session.tlsFingerprint!);
    addTearDown(() => client.close(force: true));
    final uri = Uri(
      scheme: 'https',
      host: InternetAddress.loopbackIPv4.address,
      port: session.port,
      path: '/v1/incoming/audio',
      queryParameters: const {'filename': 'blocked.mp3'},
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
      socket.write(_rawContentLengthHeaders(session, 'too-big.bin', 5));
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
        _rawChunkedHeaders(session, 'chunked-too-big.bin') + '5\r\n12345\r\n',
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
    socket.write(_rawContentLengthHeaders(session, 'low-space.bin', 4));
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
    socket.write(_rawContentLengthHeaders(session, 'unknown-space.bin', 4));
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

  test('total upload deadline applies while chunks continue arriving', () async {
    service = createService(
      maxIncomingAudioBytes: 1024,
      idleTimeout: const Duration(seconds: 2),
      totalTimeout: const Duration(milliseconds: 250),
    );
    final session = await service.startSharing(const []);
    final socket = await _openPinnedSocket(session);
    addTearDown(socket.destroy);
    socket.write(
      _rawChunkedHeaders(session, 'total-timeout.bin') + '1\r\nx\r\n',
    );
    await socket.flush();
    var responseFinished = false;
    final responseFuture = _readRawResponse(socket).then((response) {
      responseFinished = true;
      return response;
    });

    for (var index = 0; index < 20 && !responseFinished; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (responseFinished) break;
      try {
        socket.write('1\r\nx\r\n');
        await socket.flush();
      } on SocketException {
        break;
      } on TlsException {
        break;
      }
    }

    final response = await responseFuture;
    expect(response, startsWith('HTTP/1.1 408'));
    expect(response, contains('upload_total_timeout'));
    expect(await incomingDirectory.list().toList(), isEmpty);
  });

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
      'Bearer ' + session.token,
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
      'Bearer ' + session.token,
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
      .transform(utf8.decoder)
      .join()
      .timeout(const Duration(seconds: 5));
}

String _rawContentLengthHeaders(
  MediaHubSession session,
  String filename,
  int length,
) {
  return 'POST /v1/incoming/audio?filename=' +
      Uri.encodeQueryComponent(filename) +
      ' HTTP/1.1\r\nHost: 127.0.0.1:' +
      session.port.toString() +
      '\r\nAuthorization: Bearer ' +
      session.token +
      '\r\nContent-Length: ' +
      length.toString() +
      '\r\nConnection: close\r\n\r\n';
}

String _rawChunkedHeaders(MediaHubSession session, String filename) {
  return 'POST /v1/incoming/audio?filename=' +
      Uri.encodeQueryComponent(filename) +
      ' HTTP/1.1\r\nHost: 127.0.0.1:' +
      session.port.toString() +
      '\r\nAuthorization: Bearer ' +
      session.token +
      '\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n';
}

HttpClient _pinnedHttpClient(String fingerprint) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.badCertificateCallback = (certificate, host, port) =>
      mediaHubTlsFingerprint(certificate.der) == fingerprint.toLowerCase();
  return client;
}
