import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Media Hub insecure transport consent contracts', () {
    late String source;

    setUpAll(() async {
      source = await File(
        'lib/features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart',
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

    test('starting sharing requires affirmative risk consent', () {
      final start = source.indexOf('Future<void> _start()');
      final end = source.indexOf('Future<bool> _confirmInsecureSharing()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(method, contains('if (!await _confirmInsecureSharing()) return;'));
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
