enum MediaHubEndpointKind {
  tailscale,
  lan,
  other,
}

class MediaHubEndpoint {
  final String host;
  final int port;
  final MediaHubEndpointKind kind;

  const MediaHubEndpoint({
    required this.host,
    required this.port,
    required this.kind,
  });

  bool get isRemoteCapable => kind == MediaHubEndpointKind.tailscale;

  Uri get baseUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
      );

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'kind': kind.name,
      'remoteCapable': isRemoteCapable,
    };
  }
}

class MediaHubSession {
  final String host;
  final int port;
  final String token;
  final DateTime startedAt;
  final int trackCount;
  final List<MediaHubEndpoint> endpoints;

  /// Stable identity of this desktop installation. Older sessions can leave it
  /// null; once present it lets paired clients recognize the same computer even
  /// when its address changes.
  final String? deviceId;

  const MediaHubSession({
    required this.host,
    required this.port,
    required this.token,
    required this.startedAt,
    required this.trackCount,
    this.endpoints = const [],
    this.deviceId,
  });

  Uri get baseUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
      );

  MediaHubEndpoint? get tailscaleEndpoint {
    for (final endpoint in endpoints) {
      if (endpoint.kind == MediaHubEndpointKind.tailscale) {
        return endpoint;
      }
    }
    return null;
  }

  bool get remoteAccessAvailable => tailscaleEndpoint != null;

  Uri get pairingUri => Uri(
        scheme: 'lyricforge',
        host: 'media-hub',
        path: '/connect',
        queryParameters: {
          'v': '1',
          'host': host,
          'port': port.toString(),
          'token': token,
          'transport': remoteAccessAvailable ? 'tailscale' : 'lan',
          if (deviceId?.trim().isNotEmpty == true) 'deviceId': deviceId!.trim(),
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
