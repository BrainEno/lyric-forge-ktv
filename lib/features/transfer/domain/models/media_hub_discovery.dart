class MediaHubDiscoveryResult {
  final String deviceId;
  final String host;
  final int port;
  final String token;
  final String tlsFingerprint;

  const MediaHubDiscoveryResult({
    required this.deviceId,
    required this.host,
    required this.port,
    required this.token,
    required this.tlsFingerprint,
  });
}
