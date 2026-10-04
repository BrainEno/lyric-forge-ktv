import 'dart:io';

import '../../domain/models/local_media_catalog.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';

class LocalMediaCatalogBuilder {
  const LocalMediaCatalogBuilder();

  LocalMediaCatalog build({
    required Iterable<LocalMediaLibraryEntry> entries,
    required Iterable<LocalMediaMetadata> overrides,
  }) {
    final overrideByPath = <String, LocalMediaMetadata>{
      for (final item in overrides) _pathKey(item.sourcePath): item,
    };

    final tracks = entries
        .map(
          (entry) => _resolveTrack(
            entry,
            overrideByPath[_pathKey(entry.sourcePath)],
          ),
        )
        .toList(growable: false)
      ..sort(_compareTrackTitle);

    final artists = _buildArtists(tracks);
    final albums = _buildAlbums(tracks);
    return LocalMediaCatalog(
      tracks: List<LocalCatalogTrack>.unmodifiable(tracks),
      artists: List<LocalArtistGroup>.unmodifiable(artists),
      albums: List<LocalAlbumGroup>.unmodifiable(albums),
    );
  }

  String _pathKey(String path) {
    final canonical = File(path).absolute.path;
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  LocalCatalogTrack _resolveTrack(
    LocalMediaLibraryEntry entry,
    LocalMediaMetadata? override,
  ) {
    final fallbackTitle = _fallbackTitle(entry.sourcePath);
    final embeddedTitle = _nonEmpty(entry.embeddedTitle) ?? fallbackTitle;
    final title = override?.resolvedTitle(embeddedTitle) ?? embeddedTitle;
    final artist = override?.resolvedArtist(entry.embeddedArtist) ??
        entry.embeddedArtist;
    final album = override?.resolvedAlbum(entry.embeddedAlbum) ??
        entry.embeddedAlbum;
    final artwork = override?.resolvedArtwork(entry.embeddedArtworkPath) ??
        entry.embeddedArtworkPath;

    return LocalCatalogTrack(
      sourcePath: entry.sourcePath,
      format: entry.format,
      title: title,
      artist: _nonEmpty(artist),
      album: _nonEmpty(album),
      artworkPath: _nonEmpty(artwork),
      trackNumber: entry.embeddedTrackNumber,
      year: entry.embeddedYear,
      durationMs: entry.durationMs,
      isMissing: entry.isMissing,
      hasLyrics: override?.metadata['linkedProjectId'] is String,
    );
  }

  List<LocalArtistGroup> _buildArtists(List<LocalCatalogTrack> tracks) {
    final byName = <String, _NamedTrackBucket>{};
    for (final track in tracks) {
      final name = _nonEmpty(track.artist);
      if (name == null) continue;
      final key = name.toLowerCase();
      final bucket = byName.putIfAbsent(
        key,
        () => _NamedTrackBucket(name),
      );
      bucket.tracks.add(track);
    }

    final groups = byName.values.map((bucket) {
      bucket.tracks.sort(_compareArtistTrack);
      return LocalArtistGroup(
        name: bucket.displayName,
        tracks: List<LocalCatalogTrack>.unmodifiable(bucket.tracks),
      );
    }).toList();
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  List<LocalAlbumGroup> _buildAlbums(List<LocalCatalogTrack> tracks) {
    final byTitle = <String, _NamedTrackBucket>{};
    for (final track in tracks) {
      final title = _nonEmpty(track.album);
      if (title == null) continue;
      final key = title.toLowerCase();
      final bucket = byTitle.putIfAbsent(
        key,
        () => _NamedTrackBucket(title),
      );
      bucket.tracks.add(track);
    }

    final groups = byTitle.values.map((bucket) {
      bucket.tracks.sort(_compareAlbumTrack);
      return LocalAlbumGroup(
        title: bucket.displayName,
        tracks: List<LocalCatalogTrack>.unmodifiable(bucket.tracks),
      );
    }).toList();
    groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return groups;
  }

  int _compareTrackTitle(LocalCatalogTrack a, LocalCatalogTrack b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  int _compareArtistTrack(LocalCatalogTrack a, LocalCatalogTrack b) {
    final albumCompare = (a.album ?? '').toLowerCase().compareTo(
          (b.album ?? '').toLowerCase(),
        );
    if (albumCompare != 0) return albumCompare;
    return _compareAlbumTrack(a, b);
  }

  int _compareAlbumTrack(LocalCatalogTrack a, LocalCatalogTrack b) {
    final aTrack = a.trackNumber;
    final bTrack = b.trackNumber;
    if (aTrack != null || bTrack != null) {
      if (aTrack == null) return 1;
      if (bTrack == null) return -1;
      final trackCompare = aTrack.compareTo(bTrack);
      if (trackCompare != 0) return trackCompare;
    }
    return _compareTrackTitle(a, b);
  }

  String _fallbackTitle(String path) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    return fileName.replaceAll(
      RegExp(r'\.(mp3|flac|wav|m4a|aac|ogg)$', caseSensitive: false),
      '',
    );
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _NamedTrackBucket {
  final String displayName;
  final List<LocalCatalogTrack> tracks = <LocalCatalogTrack>[];

  _NamedTrackBucket(this.displayName);
}
