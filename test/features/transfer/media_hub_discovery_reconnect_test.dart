import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/file_media_hub_device_identity_store.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_discovery.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_session.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_discovery_service.dart';

void main() {
  test('device identity remains stable across store instances', () async {
    final root = await Directory.systemTemp.createTemp('elysium_hub_identity_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final first = await FileMediaHubDeviceIdentityStore(
      rootDirectory: root,
    ).loadOrCreate();
    final second = await FileMediaHubDeviceIdentityStore(
      rootDirectory: root,
    ).loadOrCreate();

    expect(second.deviceId, first.deviceId);
    expect(second.discoveryKey, first.discoveryKey);
    expect(first.deviceId, isNotEmpty);
    expect(first.discoveryKey.length, greaterThanOrEqualTo(32));
  });

  test('pairing URI and saved connection round-trip discovery identity', () {
    final session = MediaHubSession(
      host: '192.168.1.20',
      port: 48517,
      token: 'session-token',
      startedAt: DateTime.utc(2026, 10, 8),
      trackCount: 3,
      deviceId: 'desktop-device-1',
      discoveryKey: 'paired-discovery-key',
    );

    final parsed = MediaHubConnection.fromPairingUri(session.pairingUri);
    final restored = MediaHubConnection.fromJson(parsed.toJson());

    expect(parsed.deviceId, 'desktop-device-1');
    expect(parsed.discoveryKey, 'paired-discovery-key');
    expect(parsed.supportsDiscovery, isTrue);
    expect(restored.deviceId, parsed.deviceId);
    expect(restored.discoveryKey, parsed.discoveryKey);
  });

  test('stale saved endpoint is recovered through paired discovery', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final authorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      if (request.uri.path != '/v1/health' ||
          authorization != 'Bearer fresh-token') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'status': 'ok',
          'protocolVersion': 1,
        }),
      );
      await request.response.close();
    });

    final discovery = _FakeDiscoveryService(
      MediaHubDiscoveryResult(
        deviceId: 'desktop-device-1',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        token: 'fresh-token',
      ),
    );
    MediaHubConnection? persisted;
    final client = HttpMediaHubClientService(
      discoveryService: discovery,
      onConnectionResolved: (connection) {
        persisted = connection;
      },
    );
    addTearDown(client.dispose);

    const stale = MediaHubConnection(
      host: '127.0.0.1',
      port: 1,
      token: 'expired-token',
      deviceId: 'desktop-device-1',
      discoveryKey: 'paired-discovery-key',
    );

    await client.connectTo(stale);

    expect(discovery.calls, 1);
    expect(client.currentConnection?.host, InternetAddress.loopbackIPv4.address);
    expect(client.currentConnection?.port, server.port);
    expect(client.currentConnection?.token, 'fresh-token');
    expect(client.currentConnection?.deviceId, 'desktop-device-1');
    expect(client.currentConnection?.discoveryKey, 'paired-discovery-key');
    expect(persisted?.port, server.port);
    expect(persisted?.token, 'fresh-token');
  });

  test('legacy connection without device identity does not invoke discovery',
      () async {
    final discovery = _FakeDiscoveryService(null);
    final client = HttpMediaHubClientService(discoveryService: discovery);
    addTearDown(client.dispose);

    const legacy = MediaHubConnection(
      host: '127.0.0.1',
      port: 1,
      token: 'legacy-token',
    );

    await expectLater(
      client.connectTo(legacy),
      throwsA(isA<MediaHubClientException>()),
    );
    expect(discovery.calls, 0);
  });
}

class _FakeDiscoveryService implements MediaHubDiscoveryService {
  final MediaHubDiscoveryResult? result;
  int calls = 0;

  _FakeDiscoveryService(this.result);

  @override
  Future<MediaHubDiscoveryResult?> discover(
    MediaHubConnection knownConnection, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    calls++;
    expect(knownConnection.deviceId, 'desktop-device-1');
    expect(knownConnection.discoveryKey, 'paired-discovery-key');
    return result;
  }
}
