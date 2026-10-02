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

    final version = uri.queryParameters['v'];
    if (version != '1') {
      throw const FormatException('不支持的 Media Hub 协议版本');
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

  factory MediaHubConnection.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String?;
    final port = json['port'];
    final token = json['token'] as String?;

    if (host == null || host.isEmpty || port is! num || token == null || token.isEmpty) {
      throw const FormatException('保存的桌面连接信息无效');
    }

    final transportName = json['transport'] as String?;
    final transport = switch (transportName) {
      'tailscale' => MediaHubTransport.tailscale,
      'lan' => MediaHubTransport.lan,
      _ => MediaHubTransport.unknown,
    };

    return MediaHubConnection(
      host: host,
      port: port.toInt(),
      token: token,
      transport: transport,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'token': token,
      'transport': transport.name,
    };
  }

  Uri resolve(String location) {
    final normalized = location.startsWith('/') ? location : '/$location';
    return baseUri.resolveUri(Uri.parse(normalized));
  }
}
