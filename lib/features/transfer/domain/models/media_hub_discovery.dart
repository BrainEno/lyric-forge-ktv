class MediaHubDiscoveryResult {
  final String deviceId;
  final String host;
  final int port;
  final String token;

  const MediaHubDiscoveryResult({
    required this.deviceId,
    required this.host,
    required this.port,
    required this.token,
  });
}
