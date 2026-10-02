enum MediaHubTransport {
  tailscale,
  lan,
  unknown,
}

class MediaHubConnection {
  final String host;
  final int port;
  final String token;
  final MediaHubTransport transport;

  const MediaHubConnection({
    required this.host,
    required this.port,
    required this.token,
    this.transport = MediaHubTransport.unknown,
  });

  Uri get baseUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/',
      );

  factory MediaHubConnection.fromPairingUri(Uri uri) {
    if (uri.scheme != 'lyricforge' || uri.host != 'media-hub') {
      throw const FormatException('不是有效的 LyricForge Media Hub 配对地址');
    }

    final host = uri.queryParameters['host']?.trim();
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final token = uri.queryParameters['token']?.trim();

    if (host == null || host.isEmpty || port == null || port <= 0) {
      throw const FormatException('配对地址缺少有效的 host 或 port');
    }
    if (token == null || token.isEmpty) {
      throw const FormatException('配对地址缺少访问 token');
    }

    final transportName = uri.queryParameters['transport'];
    final transport = switch (transportName) {
      'tailscale' => MediaHubTransport.tailscale,
      'lan' => MediaHubTransport.lan,
      _ => MediaHubTransport.unknown,
    };

    return MediaHubConnection(
      host: host,
      port: port,
      token: token,
      transport: transport,
    );
  }

  Uri resolve(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(path: normalized);
  }
}
