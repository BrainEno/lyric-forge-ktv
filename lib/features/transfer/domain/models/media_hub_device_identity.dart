class MediaHubDeviceIdentity {
  final String deviceId;

  /// Stable secret shared only through explicit pairing. UDP discovery proves
  /// possession of this secret with HMAC-SHA256; the secret itself is never
  /// transmitted in discovery packets.
  final String discoveryKey;

  const MediaHubDeviceIdentity({
    required this.deviceId,
    required this.discoveryKey,
  });

  factory MediaHubDeviceIdentity.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    final discoveryKey = json['discoveryKey'] as String?;
    if (deviceId == null ||
        deviceId.trim().isEmpty ||
        discoveryKey == null ||
        discoveryKey.trim().isEmpty) {
      throw const FormatException('Media Hub 设备身份数据无效');
    }
    return MediaHubDeviceIdentity(
      deviceId: deviceId.trim(),
      discoveryKey: discoveryKey.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'discoveryKey': discoveryKey,
      };
}
