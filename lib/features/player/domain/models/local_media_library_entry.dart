class LocalMediaLibraryEntry {
  final String sourcePath;
  final String format;
  final DateTime addedAt;
  final DateTime lastSeenAt;
  final bool isMissing;
  final String? embeddedTitle;
  final String? embeddedArtist;
  final String? embeddedAlbum;
  final String? embeddedArtworkPath;
  final List<String> embeddedGenres;
  final int? embeddedTrackNumber;
  final int? embeddedYear;
  final int? durationMs;
  final int? sourceSizeBytes;
  final DateTime? sourceModifiedAt;
  final DateTime? metadataScannedAt;

  const LocalMediaLibraryEntry({
    required this.sourcePath,
    required this.format,
    required this.addedAt,
    required this.lastSeenAt,
    this.isMissing = false,
    this.embeddedTitle,
    this.embeddedArtist,
    this.embeddedAlbum,
    this.embeddedArtworkPath,
    this.embeddedGenres = const [],
    this.embeddedTrackNumber,
    this.embeddedYear,
    this.durationMs,
    this.sourceSizeBytes,
    this.sourceModifiedAt,
    this.metadataScannedAt,
  });

  bool get hasEmbeddedPresentationMetadata =>
      embeddedTitle?.trim().isNotEmpty == true ||
      embeddedArtist?.trim().isNotEmpty == true ||
      embeddedAlbum?.trim().isNotEmpty == true ||
      embeddedArtworkPath?.trim().isNotEmpty == true;

  LocalMediaLibraryEntry copyWith({
    String? sourcePath,
    String? format,
    DateTime? addedAt,
    DateTime? lastSeenAt,
    bool? isMissing,
    String? embeddedTitle,
    String? embeddedArtist,
    String? embeddedAlbum,
    String? embeddedArtworkPath,
    List<String>? embeddedGenres,
    int? embeddedTrackNumber,
    int? embeddedYear,
    int? durationMs,
    int? sourceSizeBytes,
    DateTime? sourceModifiedAt,
    DateTime? metadataScannedAt,
    bool clearEmbeddedTitle = false,
    bool clearEmbeddedArtist = false,
    bool clearEmbeddedAlbum = false,
    bool clearEmbeddedArtwork = false,
    bool clearEmbeddedTrackNumber = false,
    bool clearEmbeddedYear = false,
    bool clearDuration = false,
  }) {
    return LocalMediaLibraryEntry(
      sourcePath: sourcePath ?? this.sourcePath,
      format: format ?? this.format,
      addedAt: addedAt ?? this.addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isMissing: isMissing ?? this.isMissing,
      embeddedTitle:
          clearEmbeddedTitle ? null : embeddedTitle ?? this.embeddedTitle,
      embeddedArtist:
          clearEmbeddedArtist ? null : embeddedArtist ?? this.embeddedArtist,
      embeddedAlbum:
          clearEmbeddedAlbum ? null : embeddedAlbum ?? this.embeddedAlbum,
      embeddedArtworkPath: clearEmbeddedArtwork
          ? null
          : embeddedArtworkPath ?? this.embeddedArtworkPath,
      embeddedGenres: embeddedGenres ?? this.embeddedGenres,
      embeddedTrackNumber: clearEmbeddedTrackNumber
          ? null
          : embeddedTrackNumber ?? this.embeddedTrackNumber,
      embeddedYear:
          clearEmbeddedYear ? null : embeddedYear ?? this.embeddedYear,
      durationMs: clearDuration ? null : durationMs ?? this.durationMs,
      sourceSizeBytes: sourceSizeBytes ?? this.sourceSizeBytes,
      sourceModifiedAt: sourceModifiedAt ?? this.sourceModifiedAt,
      metadataScannedAt: metadataScannedAt ?? this.metadataScannedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'format': format,
        'addedAt': addedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'isMissing': isMissing,
        'embeddedTitle': embeddedTitle,
        'embeddedArtist': embeddedArtist,
        'embeddedAlbum': embeddedAlbum,
        'embeddedArtworkPath': embeddedArtworkPath,
        'embeddedGenres': embeddedGenres,
        'embeddedTrackNumber': embeddedTrackNumber,
        'embeddedYear': embeddedYear,
        'durationMs': durationMs,
        'sourceSizeBytes': sourceSizeBytes,
        'sourceModifiedAt': sourceModifiedAt?.toIso8601String(),
        'metadataScannedAt': metadataScannedAt?.toIso8601String(),
      };

  factory LocalMediaLibraryEntry.fromJson(Map<String, dynamic> json) {
    return LocalMediaLibraryEntry(
      sourcePath: json['sourcePath'] as String,
      format: json['format'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      isMissing: json['isMissing'] as bool? ?? false,
      embeddedTitle: json['embeddedTitle'] as String?,
      embeddedArtist: json['embeddedArtist'] as String?,
      embeddedAlbum: json['embeddedAlbum'] as String?,
      embeddedArtworkPath: json['embeddedArtworkPath'] as String?,
      embeddedGenres: json['embeddedGenres'] is List
          ? (json['embeddedGenres'] as List)
              .whereType<String>()
              .toList(growable: false)
          : const [],
      embeddedTrackNumber: json['embeddedTrackNumber'] as int?,
      embeddedYear: json['embeddedYear'] as int?,
      durationMs: json['durationMs'] as int?,
      sourceSizeBytes: json['sourceSizeBytes'] as int?,
      sourceModifiedAt: json['sourceModifiedAt'] is String
          ? DateTime.tryParse(json['sourceModifiedAt'] as String)
          : null,
      metadataScannedAt: json['metadataScannedAt'] is String
          ? DateTime.tryParse(json['metadataScannedAt'] as String)
          : null,
    );
  }
}
