import '../../../project/domain/models/lyric_document.dart';

class SharedAudioTrack {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String localPath;
  final String? artworkPath;
  final String format;
  final int byteLength;
  final Duration? duration;
  final LyricDocument? lyrics;

  const SharedAudioTrack({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    required this.localPath,
    this.artworkPath,
    required this.format,
    required this.byteLength,
    this.duration,
    this.lyrics,
  });

  bool get hasLyrics => lyrics != null && lyrics!.lines.isNotEmpty;
  bool get hasArtwork => artworkPath?.trim().isNotEmpty == true;

  Map<String, dynamic> toPublicJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'format': format,
      'byteLength': byteLength,
      'durationMs': duration?.inMilliseconds,
      'hasLyrics': hasLyrics,
      'hasArtwork': hasArtwork,
    };
  }
}
