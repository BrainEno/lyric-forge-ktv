import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_http_client_factory.dart';

void main() {
  test('manual HTTP proxy overrides environment and system proxies', () async {
    final factory = AsrDownloadHttpClientFactory(
      environment: () => const {'https_proxy': 'http://environment-proxy:8080'},
      systemProxyLookup: () async => 'http://system-proxy:8888',
    );

    final directive = await factory.resolveProxyDirective(
      manualProxy: 'http://127.0.0.1:7890',
    );

    expect(directive, 'PROXY 127.0.0.1:7890');
  });

  test('uses environment proxy before native system proxy', () async {
    final factory = AsrDownloadHttpClientFactory(
      environment: () => const {'https_proxy': 'http://environment-proxy:8080'},
      systemProxyLookup: () async => 'http://system-proxy:8888',
    );

    expect(
      await factory.resolveProxyDirective(),
      'PROXY environment-proxy:8080',
    );
  });

  test('recognizes an uppercase HTTPS proxy environment variable', () async {
    final factory = AsrDownloadHttpClientFactory(
      environment: () => const {'HTTPS_PROXY': 'http://proxy.example:3128'},
      systemProxyLookup: () async => null,
    );

    expect(await factory.resolveProxyDirective(), 'PROXY proxy.example:3128');
  });

  test(
    'falls back to native system proxy and then direct connection',
    () async {
      final systemFactory = AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => 'http://system-proxy:8888',
      );
      final directFactory = AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => null,
      );

      expect(
        await systemFactory.resolveProxyDirective(),
        'PROXY system-proxy:8888',
      );
      expect(await directFactory.resolveProxyDirective(), 'DIRECT');
    },
  );

  test('uses HTTPS proxy from Windows per-scheme proxy settings', () {
    expect(
      AsrDownloadHttpClientFactory.parseWindowsProxyServer(
        'http=local-http:8080;https=local-https:8443',
      ),
      'http://local-https:8443',
    );
    expect(
      AsrDownloadHttpClientFactory.parseWindowsProxyServer('127.0.0.1:7890'),
      'http://127.0.0.1:7890',
    );
    expect(
      () => AsrDownloadHttpClientFactory.parseWindowsProxyServer(
        'socks=127.0.0.1:1080',
      ),
      throwsFormatException,
    );
  });

  test('uses native HTTPS proxy and surfaces PAC/WPAD configuration', () {
    expect(
      AsrDownloadHttpClientFactory.parseMacOsProxySettings(
        'HTTPSProxyEnable : 1\nHTTPSProxy : proxy.example\nHTTPSPort : 8443',
      ),
      'http://proxy.example:8443',
    );
    expect(
      () => AsrDownloadHttpClientFactory.parseMacOsProxySettings(
        'ProxyAutoConfigEnable : 1',
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects unsupported, malformed, and credential-bearing proxies',
    () async {
      final factory = AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => null,
      );

      for (final value in [
        'socks5://127.0.0.1:1080',
        'https://127.0.0.1:7890',
        'http://user:password@127.0.0.1:7890',
        'http://127.0.0.1',
      ]) {
        await expectLater(
          factory.resolveProxyDirective(manualProxy: value),
          throwsFormatException,
        );
      }
    },
  );
}
