import 'audio_asset.dart';
import 'lyric_document.dart';

enum ProjectStatus {
  draft,
  importing,
  processing,
  transcribing,
  editing,
  ready,
  error,
}

enum ProcessingStage {
  none,
  audioImported,
  audioNormalized,
  vocalsSeparated,
  transcriptionComplete,
  lyricsEdited,
  exported,
}

class ProjectManifest {
  final String id;
  final String name;
  final String? artist;
  final String? album;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProjectStatus status;
  final ProcessingStage currentStage;
  final AudioAsset? audioAsset;
  final LyricDocument? lyricDocument;
  final String? projectDirectory;
  final Map<String, dynamic> metadata;

  const ProjectManifest({
    required this.id,
    required this.name,
    this.artist,
    this.album,
    required this.createdAt,
    required this.updatedAt,
    this.status = ProjectStatus.draft,
    this.currentStage = ProcessingStage.none,
    this.audioAsset,
    this.lyricDocument,
    this.projectDirectory,
    this.metadata = const {},
  });

  ProjectManifest copyWith({
    String? id,
    String? name,
    String? artist,
    String? album,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectStatus? status,
    ProcessingStage? currentStage,
    AudioAsset? audioAsset,
    LyricDocument? lyricDocument,
    String? projectDirectory,
    Map<String, dynamic>? metadata,
  }) {
    return ProjectManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      currentStage: currentStage ?? this.currentStage,
      audioAsset: audioAsset ?? this.audioAsset,
      lyricDocument: lyricDocument ?? this.lyricDocument,
      projectDirectory: projectDirectory ?? this.projectDirectory,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'album': album,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'status': status.name,
      'currentStage': currentStage.name,
      'audioAsset': audioAsset?.toJson(),
      'lyricDocument': lyricDocument?.toJson(),
      'projectDirectory': projectDirectory,
      'metadata': metadata,
    };
  }

  factory ProjectManifest.fromJson(Map<String, dynamic> json) {
    return ProjectManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      status: ProjectStatus.values.byName(json['status'] as String),
      currentStage: ProcessingStage.values.byName(json['currentStage'] as String),
      audioAsset: json['audioAsset'] != null
          ? AudioAsset.fromJson(json['audioAsset'] as Map<String, dynamic>)
          : null,
      lyricDocument: json['lyricDocument'] != null
          ? LyricDocument.fromJson(json['lyricDocument'] as Map<String, dynamic>)
          : null,
      projectDirectory: json['projectDirectory'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  bool get canPlay => audioAsset?.instrumentalPath != null;
  bool get hasLyrics => lyricDocument != null && lyricDocument!.lines.isNotEmpty;
  double get progressPercent {
    final stages = ProcessingStage.values.length - 1;
    final current = currentStage.index;
    return stages > 0 ? current / stages : 0.0;
  }
}
