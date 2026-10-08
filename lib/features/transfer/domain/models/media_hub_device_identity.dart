class MediaHubDeviceIdentity {
  final String deviceId;

  /// Stable HTTP bearer token created with this desktop installation. It is
  /// shared only through the explicit pairing URI, never through UDP discovery.
  final String accessToken;

  const MediaHubDeviceIdentity({
    required this.deviceId,
    required this.accessToken,
  });

  factory MediaHubDeviceIdentity.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    final accessToken = json['accessToken'] as String?;
    if (deviceId == null ||
        deviceId.trim().isEmpty ||
        accessToken == null ||
        accessToken.trim().isEmpty) {
      throw const FormatException('Media Hub 设备身份数据无效');
    }
    return MediaHubDeviceIdentity(
      deviceId: deviceId.trim(),
      accessToken: accessToken.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'accessToken': accessToken,
      };
}
