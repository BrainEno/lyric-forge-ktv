import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Media Hub insecure transport consent contracts', () {
    late String source;
    late String serverSource;
    late String clientSource;
    late String networkConfig;
    late String manifest;

    setUpAll(() async {
      source = await File(
        'lib/features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart',
      ).readAsString();
      serverSource = await File(
        'lib/features/transfer/data/services/http_media_hub_service.dart',
      ).readAsString();
      clientSource = await File(
        'lib/features/transfer/data/services/http_media_hub_client_service.dart',
      ).readAsString();
      networkConfig = await File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsString();
      manifest = await File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsString();
    });

    test('opening the transfer screen does not start a listener', () {
      final start = source.indexOf('Future<void> _prepare()');
      final end = source.indexOf('Future<void> _refreshAndRestart()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final prepare = source.substring(start, end);

      expect(prepare, isNot(contains('_hub.startSharing(')));
      expect(prepare, contains('_catalog.build()'));
    });

    test('HTTP service does not bind wildcard/public interfaces', () {
      expect(serverSource, isNot(contains('InternetAddress.anyIPv4')));
      expect(serverSource, contains('_bindWithPortFallback(host)'));
      expect(serverSource, contains('_isTailscaleIpv4(value)'));
      expect(serverSource, contains('_isPrivateLanIpv4(value)'));
      expect(serverSource, isNot(contains('otherHosts.add(value)')));
    });

    test('Media Hub traffic requires pinned HTTPS and bearer headers', () {
      expect(serverSource, contains('HttpServer.bindSecure('));
      expect(serverSource, contains("'protocolVersion': 2"));
      expect(
        serverSource,
        isNot(contains("request.uri.queryParameters['token']")),
      );
      expect(clientSource, contains('badCertificateCallback'));
      expect(clientSource, contains('mediaHubTlsFingerprint(certificate.der)'));
      expect(clientSource, contains('connection.tlsFingerprint'));
    });

    test('Android only permits cleartext for the loopback playback proxy', () {
      expect(
        networkConfig,
        contains('<base-config cleartextTrafficPermitted="false">'),
      );
      expect(
        networkConfig,
        contains('<domain includeSubdomains="false">127.0.0.1</domain>'),
      );
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    });

    test(
      'audio and artwork metadata no longer carry session tokens in URLs',
      () async {
        expect(clientSource, isNot(contains("'token': connection.token")));
        final proxySource = await File(
          'lib/features/transfer/data/services/media_hub_rebinding_audio_player_service.dart',
        ).readAsString();
        expect(proxySource, contains('InternetAddress.loopbackIPv4'));
        expect(proxySource, contains('HttpHeaders.authorizationHeader'));
      },
    );
    test('starting sharing requires affirmative risk consent', () {
      final start = source.indexOf('Future<void> _start()');
      final end = source.indexOf(
        'Future<bool> _confirmInsecureSharing()',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(
        method,
        contains('if (!await _confirmInsecureSharing() || !mounted) return;'),
      );
      expect(method, contains('await _hub.startSharing(tracks)'));
    });

    test('HTTP warning covers LAN exposure and Tailscale boundary', () {
      expect(source, contains('明文 HTTP'));
      expect(source, contains('截获配对令牌'));
      expect(source, contains('公共 Wi-Fi'));
      expect(source, contains('Tailscale 隧道加密'));
      expect(source, contains('我了解风险，继续'));
    });

    test('refreshing while stopped does not open the listener', () {
      final start = source.indexOf('Future<void> _refreshAndRestart()');
      final end = source.indexOf('Future<void> _start()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(method, contains('final wasRunning = _hub.isRunning;'));
      expect(
        method,
        contains(
          'if (wasRunning) {\n        await _hub.startSharing(tracks);\n      }',
        ),
      );
    });
  });
}
