import 'dart:io';

import '../../../player/domain/repositories/local_media_library_repository.dart';
import '../../../player/domain/repositories/local_media_metadata_repository.dart';
import '../../domain/models/shared_audio_track.dart';

/// Builds the desktop Media Hub share list from the same persistent local
/// library used by the regular player.
///
/// User-edited presentation metadata has the same priority here as in local
/// playback: override > embedded file tag > file-name fallback. This keeps the
/// phone's remote catalog visually aligned with the desktop Library.
class LocalLibraryMediaShareCatalog {
  final LocalMediaLibraryRepository libraryRepository;
  final LocalMediaMetadataRepository? metadataRepository;

  const LocalLibraryMediaShareCatalog({
    required this.libraryRepository,
    this.metadataRepository,
  });

  Future<List<SharedAudioTrack>> build() async {
    final entries = await libraryRepository.getAll();
    final tracks = <SharedAudioTrack>[];

    for (final entry in entries) {
      if (entry.isMissing) continue;

      final file = File(entry.sourcePath);
      if (!await file.exists()) continue;

      final override = await metadataRepository?.getForAudio(entry.sourcePath);
      final fileName = file.uri.pathSegments.isEmpty
          ? entry.sourcePath
          : file.uri.pathSegments.last;
      final embeddedTitle = entry.embeddedTitle?.trim().isNotEmpty == true
          ? entry.embeddedTitle!.trim()
          : _titleFromFileName(fileName);
      final title = override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;
      final artist = override?.resolvedArtist(entry.embeddedArtist) ??
          _nonEmpty(entry.embeddedArtist);
      final album = override?.resolvedAlbum(entry.embeddedAlbum) ??
          _nonEmpty(entry.embeddedAlbum);
      final resolvedArtwork =
          override?.resolvedArtwork(entry.embeddedArtworkPath) ??
              entry.embeddedArtworkPath;
      final artworkPath = await _existingArtworkPath(resolvedArtwork);
      final byteLength = entry.sourceSizeBytes ?? await file.length();
      final format = entry.format.trim().isNotEmpty
          ? entry.format.trim().toLowerCase()
          : _extensionFromFileName(fileName);

      tracks.add(
        SharedAudioTrack(
          id: _stableTrackId(entry.sourcePath),
          title: title,
          artist: _nonEmpty(artist),
          album: _nonEmpty(album),
          localPath: entry.sourcePath,
          artworkPath: artworkPath,
          format: format,
          byteLength: byteLength,
          duration: entry.durationMs == null
              ? null
              : Duration(milliseconds: entry.durationMs!),
        ),
      );
    }

    tracks.sort((a, b) {
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (byTitle != 0) return byTitle;
      return a.localPath.compareTo(b.localPath);
    });
    return List.unmodifiable(tracks);
  }

  Future<String?> _existingArtworkPath(String? value) async {
    final path = _nonEmpty(value);
    if (path == null) return null;
    return await File(path).exists() ? path : null;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String _extensionFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _stableTrackId(String path) {
    // A compact deterministic FNV-1a style hash is sufficient for a session
    // catalog and avoids leaking the absolute desktop path into phone URLs.
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'library-${hash.toRadixString(16)}';
  }
}
