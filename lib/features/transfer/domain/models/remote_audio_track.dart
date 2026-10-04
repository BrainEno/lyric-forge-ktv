class RemoteAudioTrack {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String format;
  final int byteLength;
  final Duration? duration;
  final String streamPath;
  final String downloadPath;
  final bool hasLyrics;
  final String? lyricsPath;

  const RemoteAudioTrack({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.format,
    required this.byteLength,
    this.duration,
    required this.streamPath,
    required this.downloadPath,
    this.hasLyrics = false,
    this.lyricsPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'format': format,
      'byteLength': byteLength,
      'durationMs': duration?.inMilliseconds,
      'streamPath': streamPath,
      'downloadPath': downloadPath,
      'hasLyrics': hasLyrics,
      'lyricsPath': lyricsPath,
    };
  }

  factory RemoteAudioTrack.fromJson(Map<String, dynamic> json) {
    final durationMs = json['durationMs'];
    return RemoteAudioTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      format: json['format'] as String,
      byteLength: (json['byteLength'] as num).toInt(),
      duration: durationMs is num
          ? Duration(milliseconds: durationMs.toInt())
          : null,
      streamPath: json['streamPath'] as String,
      downloadPath: json['downloadPath'] as String,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
      lyricsPath: json['lyricsPath'] as String?,
    );
  }
}
