class LocalMediaLibraryEntry {
  final String sourcePath;
  final String format;
  final DateTime addedAt;
  final DateTime lastSeenAt;
  final bool isMissing;

  const LocalMediaLibraryEntry({
    required this.sourcePath,
    required this.format,
    required this.addedAt,
    required this.lastSeenAt,
    this.isMissing = false,
  });

  LocalMediaLibraryEntry copyWith({
    String? sourcePath,
    String? format,
    DateTime? addedAt,
    DateTime? lastSeenAt,
    bool? isMissing,
  }) {
    return LocalMediaLibraryEntry(
      sourcePath: sourcePath ?? this.sourcePath,
      format: format ?? this.format,
      addedAt: addedAt ?? this.addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isMissing: isMissing ?? this.isMissing,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'format': format,
        'addedAt': addedAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'isMissing': isMissing,
      };

  factory LocalMediaLibraryEntry.fromJson(Map<String, dynamic> json) {
    return LocalMediaLibraryEntry(
      sourcePath: json['sourcePath'] as String,
      format: json['format'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      isMissing: json['isMissing'] as bool? ?? false,
    );
  }
}
