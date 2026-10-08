class MediaHubDeviceIdentity {
  final String deviceId;
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
