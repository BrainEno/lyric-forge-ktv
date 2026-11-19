import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';

/// [project] carrying the lyrics of an imported lyric file for one song.
///
/// Shared by 导入歌词 on a library song and by pairing files found in the
/// library folder, so both produce the same project: the song's title and
/// audio, the imported document, a stage that says whether it still needs
/// timing, and up to three backups of lyrics it replaced.
///
/// [source] is stored as `lyricSource`; [automatic] marks a pairing nobody
/// confirmed, so the editor and support can tell the two apart.
ProjectManifest projectWithImportedLyrics(
  ProjectManifest project, {
  required String title,
  required String? artist,
  required AudioAsset audioAsset,
  required String? artworkPath,
  required LyricImportResult result,
  required DateTime now,
  String source = 'imported-file',
  bool automatic = false,
}) {
  final importedAt = now.toIso8601String();
  final timed = result.document.metadata['timed'] == true;
  final backups = nextLyricBackups(project, now: now);
  final document = result.document.copyWith(
    metadata: {
      ...result.document.metadata,
      'detectedEncoding': result.detectedEncoding,
      'importedAt': importedAt,
    },
  );
  return project.copyWith(
    name: title,
    artist: artist ?? result.artist,
    album: project.album ?? result.album,
    audioAsset: audioAsset.copyWith(
      thumbnailPath: artworkPath ?? audioAsset.thumbnailPath,
    ),
    lyricDocument: document,
    status: timed ? ProjectStatus.ready : ProjectStatus.editing,
    currentStage: timed
        ? ProcessingStage.lyricsEdited
        : ProcessingStage.transcriptionComplete,
    metadata: {
      ...project.metadata,
      'lyricSource': source,
      'lyricImport': {
        'path': result.sourcePath,
        'format': result.format.name,
        'encoding': result.detectedEncoding,
        'timed': timed,
        'importedAt': importedAt,
        if (automatic) 'automatic': true,
      },
      if (backups.isNotEmpty) 'lyricBackups': backups,
    },
  );
}

/// The backups to keep when [project]'s lyrics are about to be replaced:
/// the current document first, then at most two older ones.
List<Map<String, dynamic>> nextLyricBackups(
  ProjectManifest project, {
  required DateTime now,
}) {
  final document = project.lyricDocument;
  if (!project.hasLyrics || document == null) return const [];
  final existing = <Map<String, dynamic>>[];
  final raw = project.metadata['lyricBackups'];
  if (raw is List) {
    for (final entry in raw) {
      if (entry is Map) existing.add(Map<String, dynamic>.from(entry));
    }
  }
  existing.insert(0, {
    'createdAt': now.toIso8601String(),
    'reason': 'replaced-by-import',
    'document': document.toJson(),
  });
  return existing.take(3).toList(growable: false);
}
