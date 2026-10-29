import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_tls_identity_store.dart';

void main() {
  late Directory temp;
  late Directory incomingDirectory;
  late HttpMediaHubService service;
  final imported = <String>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lyricforge-incoming-');
    incomingDirectory = Directory(
      '${temp.path}${Platform.pathSeparator}incoming',
    );
    imported.clear();
    service = HttpMediaHubService(
      incomingDirectory: incomingDirectory,
      tlsIdentityStore: MediaHubTlsIdentityStore(
        rootDirectory: Directory('${temp.path}${Platform.pathSeparator}tls'),
      ),
      onIncomingFile: (path) async {
        imported.add(path);
      },
    );
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

  test(
    'concurrent same-name uploads preserve both complete file hashes',
    () async {
      final session = await service.startSharing(const []);
      final clientA = _pinnedHttpClient(session.tlsFingerprint!);
      final clientB = _pinnedHttpClient(session.tlsFingerprint!);
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
        upload(clientA, bytesA),
        upload(clientB, bytesB),
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
    },
  );

  test('failed library import removes the completed incoming file', () async {
    await service.stopSharing();
    service = HttpMediaHubService(
      incomingDirectory: incomingDirectory,
      tlsIdentityStore: MediaHubTlsIdentityStore(
        rootDirectory: Directory('${temp.path}${Platform.pathSeparator}tls'),
      ),
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
}

HttpClient _pinnedHttpClient(String fingerprint) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
  client.badCertificateCallback = (certificate, host, port) =>
      mediaHubTlsFingerprint(certificate.der) == fingerprint.toLowerCase();
  return client;
}
