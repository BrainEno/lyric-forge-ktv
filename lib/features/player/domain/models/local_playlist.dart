class LocalPlaylist {
  final String id;
  final String name;
  final String? description;
  final List<String> sourcePaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.sourcePaths,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  LocalPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? sourcePaths,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDescription = false,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: clearDescription ? null : description ?? this.description,
      sourcePaths: sourcePaths ?? this.sourcePaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'sourcePaths': sourcePaths,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    final rawPaths = json['sourcePaths'];
    return LocalPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      sourcePaths: rawPaths is List
          ? rawPaths.whereType<String>().toList(growable: false)
          : const [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
