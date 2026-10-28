class EmbeddedAudioMetadata {
  final String sourcePath;
  final String? title;
  final String? artist;
  final String? album;
  final String? artworkPath;
  final List<String> genres;
  final int? trackNumber;
  final int? year;
  final Duration? duration;
  final int sourceSizeBytes;
  final DateTime sourceModifiedAt;
  final DateTime scannedAt;

  const EmbeddedAudioMetadata({
    required this.sourcePath,
    required this.sourceSizeBytes,
    required this.sourceModifiedAt,
    required this.scannedAt,
    this.title,
    this.artist,
    this.album,
    this.artworkPath,
    this.genres = const [],
    this.trackNumber,
    this.year,
    this.duration,
  });

  bool get hasPresentationMetadata =>
      title?.trim().isNotEmpty == true ||
      artist?.trim().isNotEmpty == true ||
      album?.trim().isNotEmpty == true ||
      artworkPath?.trim().isNotEmpty == true;
}
