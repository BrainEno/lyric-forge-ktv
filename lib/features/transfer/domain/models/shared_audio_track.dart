class SharedAudioTrack {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String localPath;
  final String format;
  final int byteLength;
  final Duration? duration;

  const SharedAudioTrack({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.localPath,
    required this.format,
    required this.byteLength,
    this.duration,
  });

  Map<String, dynamic> toPublicJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'format': format,
      'byteLength': byteLength,
      'durationMs': duration?.inMilliseconds,
    };
  }
}
