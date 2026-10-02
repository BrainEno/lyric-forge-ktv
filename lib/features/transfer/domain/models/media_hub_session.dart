class MediaHubSession {
  final String host;
  final int port;
  final String token;
  final DateTime startedAt;
  final int trackCount;

  const MediaHubSession({
    required this.host,
    required this.port,
    required this.token,
    required this.startedAt,
    required this.trackCount,
  });

  Uri get baseUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
      );

  Uri get pairingUri => Uri(
        scheme: 'lyricforge',
        host: 'media-hub',
        path: '/connect',
        queryParameters: {
          'v': '1',
          'host': host,
          'port': port.toString(),
          'token': token,
        },
      );
}

enum MediaHubStatus {
  stopped,
  starting,
  running,
  failed,
}

class MediaHubState {
  final MediaHubStatus status;
  final MediaHubSession? session;
  final String? error;

  const MediaHubState({
    required this.status,
    this.session,
    this.error,
  });

  const MediaHubState.stopped()
      : status = MediaHubStatus.stopped,
        session = null,
        error = null;

  bool get isRunning => status == MediaHubStatus.running && session != null;
}
