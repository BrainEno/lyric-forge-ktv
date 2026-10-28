class LocalMediaMetadata {
  final String sourcePath;
  final String? title;
  final String? artist;
  final String? album;
  final String? artworkPath;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;

  const LocalMediaMetadata({
    required this.sourcePath,
    this.title,
    this.artist,
    this.album,
    this.artworkPath,
    required this.updatedAt,
    this.metadata = const {},
  });

  bool get hasOverrides =>
      title?.trim().isNotEmpty == true ||
      artist?.trim().isNotEmpty == true ||
      album?.trim().isNotEmpty == true ||
      artworkPath?.trim().isNotEmpty == true;

  String resolvedTitle(String fallback) {
    final value = title?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String? resolvedArtist(String? fallback) {
    final value = artist?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String? resolvedAlbum(String? fallback) {
    final value = album?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String? resolvedArtwork(String? fallback) {
    final value = artworkPath?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  LocalMediaMetadata copyWith({
    String? sourcePath,
    String? title,
    String? artist,
    String? album,
    String? artworkPath,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
    bool clearTitle = false,
    bool clearArtist = false,
    bool clearAlbum = false,
    bool clearArtwork = false,
  }) {
    return LocalMediaMetadata(
      sourcePath: sourcePath ?? this.sourcePath,
      title: clearTitle ? null : title ?? this.title,
      artist: clearArtist ? null : artist ?? this.artist,
      album: clearAlbum ? null : album ?? this.album,
      artworkPath: clearArtwork ? null : artworkPath ?? this.artworkPath,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkPath': artworkPath,
        'updatedAt': updatedAt.toIso8601String(),
        'metadata': metadata,
      };

  factory LocalMediaMetadata.fromJson(Map<String, dynamic> json) {
    return LocalMediaMetadata(
      sourcePath: json['sourcePath'] as String,
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artworkPath: json['artworkPath'] as String?,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
    );
  }
}
